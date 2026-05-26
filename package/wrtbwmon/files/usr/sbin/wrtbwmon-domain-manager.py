#!/usr/bin/env python3
"""Domain tracking manager — Python rewrite.

Replaces wrtbwmon-domain-manager.sh for all operations.

Key optimization: rebuilds all domain nft chains/sets/rules in 2 subprocess calls:
  1. nft list table   — read current state once
  2. nft -f -         — apply all changes as a single atomic batch

vs the shell version which made O(N×D×I×K) individual nft subprocess calls
(~10,000+ calls for a single active device = 8-17 minutes on a router).
"""

import os
import sys
import sqlite3
import subprocess
import time
import re
import fcntl
import socket

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
NFT_TABLE = os.environ.get("NFT_TABLE", "netdev wrtbwmon_acct")
DOMAIN_CHAIN = "wrtbwmon_domains"
DISPATCH_MAP = "wrtbwmon_domain_dispatch_v4"
LOCK_DIR = "/var/run"

MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
IP_RE = re.compile(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
DOMAIN_RE = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,252}[a-zA-Z0-9])?$')


def validate_mac(mac):
    return bool(mac and MAC_RE.match(mac))


def validate_ip(ip):
    if not ip or not IP_RE.match(ip):
        return False
    return all(0 <= int(o) <= 255 for o in ip.split('.'))


def validate_domain(domain):
    return bool(domain and len(domain) <= 253 and DOMAIN_RE.match(domain))


def mac_to_chain(mac):
    return f"device_domains_{mac.replace(':', '')}"


def domain_to_set(mac, domain):
    mac_clean = mac.replace(':', '')
    dom_clean = re.sub(r'[^a-zA-Z0-9_]', '_', domain)[:200]
    return f"d_{mac_clean}_{dom_clean}"


def get_db():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-1000")
    return conn


def acquire_lock(cmd):
    lock_file = f"{LOCK_DIR}/wrtbwmon-domain-{cmd}.lock"
    try:
        fd = os.open(lock_file, os.O_CREAT | os.O_WRONLY)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (IOError, OSError):
        return None


def uci_get(path, default=""):
    try:
        result = subprocess.run(["uci", "-q", "get", path], capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return default


def monitoring_enabled():
    return uci_get("wrtbwmon.general.enabled", "0") == "1"


def domain_tracking_enabled():
    return monitoring_enabled() and uci_get("wrtbwmon.general.domain_tracking", "0") == "1"


def execute_nft_batch(batch_lines, timeout=60):
    """Execute nft commands as a single batch. Returns True on success."""
    if not batch_lines:
        return True
    try:
        proc = subprocess.run(
            ["nft", "-f", "-"],
            input="\n".join(batch_lines) + "\n",
            capture_output=True, text=True, timeout=timeout
        )
        if proc.returncode != 0 and proc.stderr:
            for line in proc.stderr.splitlines():
                if "already exists" not in line and line.strip():
                    print(f"nft: {line}", file=sys.stderr)
        return proc.returncode == 0
    except subprocess.TimeoutExpired:
        print("nft batch timed out", file=sys.stderr)
        return False
    except Exception as e:
        print(f"nft batch error: {e}", file=sys.stderr)
        return False


def get_nft_state():
    """Read nft table state once. Returns dict with chains, sets, rules, map_keys."""
    state = {"chains": set(), "sets": set(), "rules": set(), "map_keys": set(), "elements": {}}
    try:
        result = subprocess.run(
            ["nft", "list", "sets"] + NFT_TABLE.split(),
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            s = line.strip()
            m = re.match(r'(?:set|map) (\S+)', s)
            if m:
                state["sets"].add(m.group(1))
        result = subprocess.run(
            ["nft", "list", "chain"] + NFT_TABLE.split() + [DOMAIN_CHAIN],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            state["chains"].add(DOMAIN_CHAIN)
        result = subprocess.run(
            ["nft", "list", "map"] + NFT_TABLE.split() + [DISPATCH_MAP],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            state["sets"].add(DISPATCH_MAP)
            for line in result.stdout.splitlines():
                m = re.search(r'(\d+\.\d+\.\d+\.\d+)\s*:', line)
                if m:
                    state["map_keys"].add(m.group(1))
    except Exception as e:
        print(f"Warning: could not read nft state: {e}", file=sys.stderr)
    return state


def get_set_elements(set_name, state):
    if set_name in state["elements"]:
        return state["elements"][set_name]
    elements = set()
    try:
        result = subprocess.run(
            ["nft", "list", "set"] + NFT_TABLE.split() + [set_name],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for ip in re.findall(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', result.stdout):
                if validate_ip(ip):
                    elements.add(ip)
    except Exception:
        pass
    state["elements"][set_name] = elements
    return elements


def collect_existing_domain_rules(state, device_domains, device_ips):
    existing_jumps = set()
    for mac in device_domains:
        chain_name = mac_to_chain(mac)
        device_ip = device_ips.get(mac)
        if device_ip:
            ip_chain = "device_" + device_ip.replace(".", "_")
            try:
                result = subprocess.run(
                    ["nft", "list", "chain"] + NFT_TABLE.split() + [ip_chain],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    state["chains"].add(ip_chain)
                    for line in result.stdout.splitlines():
                        jm = re.search(r"jump (device_domains_\S+)", line)
                        if jm:
                            existing_jumps.add(f"{ip_chain}->{jm.group(1)}")
            except Exception:
                pass
        try:
            result = subprocess.run(
                ["nft", "list", "chain"] + NFT_TABLE.split() + [chain_name],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                state["chains"].add(chain_name)
                for line in result.stdout.splitlines():
                    m = re.search(r'comment "([^"]+)"', line)
                    if m:
                        state["rules"].add(f"{chain_name}:{m.group(1)}")
        except Exception:
            pass
    return existing_jumps


def get_device_ips():
    """Return mac→ip dict from ARP table."""
    mac_to_ip = {}
    try:
        r = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[3] == "lladdr":
                ip, mac = parts[0], parts[4].lower()
                if validate_ip(ip) and validate_mac(mac):
                    mac_to_ip[mac] = ip
    except Exception:
        pass
    return mac_to_ip


def ensure_db_tables(conn):
    """Create new domain tracking tables. Drop legacy tables on first run (idempotent)."""
    # Drop legacy tables only if they still exist (one-time migration)
    legacy = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('traffic','domain_traffic','domain_traffic_log','domain_daily')"
    ).fetchall()]
    if legacy:
        for t in legacy:
            conn.execute(f"DROP TABLE IF EXISTS {t}")
        conn.commit()

    conn.executescript("""
CREATE TABLE IF NOT EXISTS domain_traffic_daily (
    mac TEXT NOT NULL,
    domain TEXT NOT NULL,
    date TEXT NOT NULL,
    bytes_down INTEGER NOT NULL DEFAULT 0,
    bytes_up INTEGER NOT NULL DEFAULT 0,
    last_seen INTEGER,
    last_counter_dl INTEGER NOT NULL DEFAULT 0,
    last_counter_ul INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(mac, domain, date)
);
CREATE INDEX IF NOT EXISTS idx_dtd_date ON domain_traffic_daily(date DESC);
CREATE INDEX IF NOT EXISTS idx_dtd_mac_date ON domain_traffic_daily(mac, date DESC);

CREATE TABLE IF NOT EXISTS ip_domain_cache (
    ip TEXT NOT NULL,
    domain TEXT NOT NULL,
    expires INTEGER NOT NULL,
    PRIMARY KEY(ip, domain)
);
CREATE INDEX IF NOT EXISTS idx_idc_expires ON ip_domain_cache(expires);
CREATE INDEX IF NOT EXISTS idx_idc_domain ON ip_domain_cache(domain);
""")
    conn.commit()


def cmd_init(conn):
    """Rebuild all domain nft chains/sets/rules from ip_domain_cache.

    Complexity: O(1) nft subprocess calls regardless of domain count.
    Before: O(N×D×I×6) shell subprocesses (~10,000+ for one device).
    After:  2 subprocess calls total (1 list + 1 batch write).
    """
    now = int(time.time())

    print("Reading nft state...", file=sys.stderr)
    state = get_nft_state()
    device_ips = get_device_ips()

    print("Querying active domains from cache...", file=sys.stderr)
    rows = conn.execute("""
        SELECT DISTINCT dtd.mac, dtd.domain, idc.ip
        FROM domain_traffic_daily dtd
        JOIN ip_domain_cache idc ON dtd.domain = idc.domain
        WHERE dtd.date >= date('now','localtime','-7 days')
          AND idc.expires > ?
        ORDER BY dtd.mac, dtd.domain
    """, (now,)).fetchall()

    device_domains = {}
    for row in rows:
        mac = row[0].lower()
        domain, ip = row[1], row[2]
        if not (validate_mac(mac) and validate_domain(domain) and validate_ip(ip)):
            continue
        device_domains.setdefault(mac, {}).setdefault(domain, set()).add(ip)

    # Bootstrap: if domain_traffic_daily is empty, seed domain chains from
    # ip_domain_cache for all ARP-visible devices so counters can start
    if not device_domains and device_ips:
        print("Bootstrapping domain chains from ip_domain_cache...", file=sys.stderr)
        cache_rows = conn.execute("""
            SELECT DISTINCT domain, ip FROM ip_domain_cache
            WHERE expires > ?
        """, (now,)).fetchall()
        if cache_rows:
            for mac, ip in device_ips.items():
                for crow in cache_rows:
                    domain, dip = crow[0], crow[1]
                    if validate_domain(domain) and validate_ip(dip):
                        device_domains.setdefault(mac, {}).setdefault(domain, set()).add(dip)

    batch = []

    # Track existing jumps as ip_chain->domain_chain pairs
    existing_jumps = collect_existing_domain_rules(state, device_domains, device_ips)

    # Clean up legacy domain dispatch chain/map if present (replaced by jump approach)
    if DOMAIN_CHAIN in state["chains"]:
        batch.append(f'flush chain {NFT_TABLE} {DOMAIN_CHAIN}')
        batch.append(f'delete chain {NFT_TABLE} {DOMAIN_CHAIN}')
    if DISPATCH_MAP in state["sets"]:
        batch.append(f'flush map {NFT_TABLE} {DISPATCH_MAP}')
        batch.append(f'delete map {NFT_TABLE} {DISPATCH_MAP}')

    domain_count = 0
    for mac, domains in device_domains.items():
        chain_name = mac_to_chain(mac)

        if chain_name not in state["chains"]:
            batch.append(f'add chain {NFT_TABLE} {chain_name}')

        # Wire: add jump from device_<ip> chain → device_domains_<mac> chain
        device_ip = device_ips.get(mac)
        if device_ip:
            ip_chain = "device_" + device_ip.replace(".", "_")
            jump_key = f"{ip_chain}->{chain_name}"
            if ip_chain in state["chains"] and jump_key not in existing_jumps:
                batch.append(f"add rule {NFT_TABLE} {ip_chain} jump {chain_name}")
                existing_jumps.add(jump_key)

        for domain, ips in domains.items():
            set_name = domain_to_set(mac, domain)
            dl_set_name = f"{set_name}_dl"

            if set_name not in state["sets"]:
                batch.append(
                    f'add set {NFT_TABLE} {set_name} '
                    f'{{ type ipv4_addr; flags interval; comment "{domain}"; }}'
                )
                ul_missing = ips
            else:
                ul_existing = get_set_elements(set_name, state)
                ul_missing = [ip for ip in ips if ip not in ul_existing]
            if f"{chain_name}:domain_ul:{domain}" not in state["rules"]:
                batch.append(
                    f'add rule {NFT_TABLE} {chain_name} '
                    f'ip daddr @{set_name} counter comment "domain_ul:{domain}"'
                )

            if dl_set_name not in state["sets"]:
                batch.append(
                    f'add set {NFT_TABLE} {dl_set_name} '
                    f'{{ type ipv4_addr; flags interval; comment "{domain}"; }}'
                )
                dl_missing = ips
            else:
                dl_existing = get_set_elements(dl_set_name, state)
                dl_missing = [ip for ip in ips if ip not in dl_existing]
            if f"{chain_name}:domain_dl:{domain}" not in state["rules"]:
                batch.append(
                    f'add rule {NFT_TABLE} {chain_name} '
                    f'ip saddr @{dl_set_name} counter comment "domain_dl:{domain}"'
                )

            for ip in ul_missing:
                batch.append(f'add element {NFT_TABLE} {set_name} {{ {ip} }}')
            for ip in dl_missing:
                batch.append(f'add element {NFT_TABLE} {dl_set_name} {{ {ip} }}')

            domain_count += 1

    print(
        f"Applying {len(batch)} nft operations "
        f"({domain_count} domains, {len(device_domains)} devices)...",
        file=sys.stderr
    )

    if batch:
        execute_nft_batch(batch)

    # Device dispatch ensured by wrtbwmon update (separate from domain dispatch)

    print(
        f"Init complete: {domain_count} domains for {len(device_domains)} devices",
        file=sys.stderr
    )
    return 0


def _ensure_device_dispatch(state=None):
    """Ensure wrtbwmon device traffic dispatch rules exist in the fw4 forward chain.
    Returns True if all rules were already present (stamp can be written).
    """
    try:
        r = subprocess.run(
            ["nft", "list", "chain"] + NFT_TABLE.split() + ["forward"],
            capture_output=True, text=True, timeout=5
        )
        fwd = r.stdout
    except Exception:
        return False

    batch = []
    if "wrtbwmon-dispatch-v4-up" not in fwd:
        batch += [
            f'insert rule {NFT_TABLE} forward ip saddr vmap @wrtbwmon_dispatch_v4 comment "wrtbwmon-dispatch-v4-up"',
            f'insert rule {NFT_TABLE} forward ip daddr vmap @wrtbwmon_dispatch_v4 comment "wrtbwmon-dispatch-v4-down"',
        ]
    if "wrtbwmon-dispatch-v6-up" not in fwd:
        batch += [
            f'insert rule {NFT_TABLE} forward ip6 saddr vmap @wrtbwmon_dispatch_v6 comment "wrtbwmon-dispatch-v6-up"',
            f'insert rule {NFT_TABLE} forward ip6 daddr vmap @wrtbwmon_dispatch_v6 comment "wrtbwmon-dispatch-v6-down"',
        ]
    if batch:
        execute_nft_batch(batch)
        return False  # rules were missing, don't stamp yet
    return True  # all rules present


_DISPATCH_STAMP = "/tmp/wrtbwmon-dispatch-ok"
_DISPATCH_TTL   = 300  # re-check every 5 minutes


def cmd_ensure_dispatch():
    """Quick check/restore for device dispatch rules. Called every minute by wrtbwmon update.
    Caches result in a stamp file — skips the nft call if rules were confirmed <5 min ago.
    """
    now = int(time.time())
    try:
        with open(_DISPATCH_STAMP) as f:
            if now - int(f.read().strip()) < _DISPATCH_TTL:
                return 0  # known-good, skip nft list chain
    except Exception:
        pass

    ok = _ensure_device_dispatch()
    if ok:
        try:
            with open(_DISPATCH_STAMP, "w") as f:
                f.write(str(now))
        except Exception:
            pass
    return 0


def cmd_add(mac, domain, ip):
    """Add a single domain tracking rule for a device. Uses batch nft."""
    if not validate_mac(mac):
        print(f"Invalid MAC: {mac}", file=sys.stderr)
        return 1
    if not validate_domain(domain):
        print(f"Invalid domain: {domain}", file=sys.stderr)
        return 1
    if not validate_ip(ip):
        print(f"Invalid IP: {ip}", file=sys.stderr)
        return 1

    chain_name = mac_to_chain(mac)
    set_name = domain_to_set(mac, domain)
    dl_set_name = f"{set_name}_dl"

    state = get_nft_state()
    device_ips = get_device_ips()

    batch = []
    if chain_name not in state["chains"]:
        batch.append(f'add chain {NFT_TABLE} {chain_name}')

    device_ip = device_ips.get(mac.lower())
    if device_ip and device_ip not in state["map_keys"]:
        batch.append(
            f'add element {NFT_TABLE} {DISPATCH_MAP} '
            f'{{ {device_ip} : jump {chain_name} }}'
        )

    if set_name not in state["sets"]:
        batch.append(
            f'add set {NFT_TABLE} {set_name} '
            f'{{ type ipv4_addr; flags interval; comment "{domain}"; }}'
        )
        batch.append(
            f'add rule {NFT_TABLE} {chain_name} '
            f'ip daddr @{set_name} counter comment "domain_ul:{domain}"'
        )

    if dl_set_name not in state["sets"]:
        batch.append(
            f'add set {NFT_TABLE} {dl_set_name} '
            f'{{ type ipv4_addr; flags interval; comment "{domain}"; }}'
        )
        batch.append(
            f'add rule {NFT_TABLE} {chain_name} '
            f'ip saddr @{dl_set_name} counter comment "domain_dl:{domain}"'
        )

    batch.append(f'add element {NFT_TABLE} {set_name} {{ {ip} }}')
    batch.append(f'add element {NFT_TABLE} {dl_set_name} {{ {ip} }}')

    execute_nft_batch(batch)
    return 0


def cmd_remove(mac, domain):
    """Remove domain tracking rule and its nft sets."""
    if not validate_mac(mac):
        return 1
    if not validate_domain(domain):
        return 1

    chain_name = mac_to_chain(mac)
    set_name = domain_to_set(mac, domain)
    dl_set_name = f"{set_name}_dl"

    batch = []
    try:
        r = subprocess.run(
            ["nft", "-a", "list", "chain"] + NFT_TABLE.split() + [chain_name],
            capture_output=True, text=True, timeout=5
        )
        for line in r.stdout.splitlines():
            if f"domain_ul:{domain}" in line or f"domain_dl:{domain}" in line:
                m = re.search(r'handle (\d+)', line)
                if m:
                    batch.append(f'delete rule {NFT_TABLE} {chain_name} handle {m.group(1)}')
    except Exception:
        pass

    batch += [
        f'delete set {NFT_TABLE} {set_name}',
        f'delete set {NFT_TABLE} {dl_set_name}',
    ]
    execute_nft_batch(batch)
    return 0


def cmd_cleanup(conn):
    """Clean up expired domain data from DB and orphaned nft chains."""
    now = int(time.time())
    domain_retention = int(os.environ.get("DOMAIN_RETENTION_DAYS", 90)) * 86400
    rule_inactive = int(os.environ.get("RULE_INACTIVE_DAYS", 7)) * 86400
    max_per_device = int(os.environ.get("MAX_DOMAINS_PER_DEVICE", 5000))

    print("Cleaning expired database records...", file=sys.stderr)
    retention_date = time.strftime("%Y-%m-%d", time.localtime(now - domain_retention))
    inactive_date = time.strftime("%Y-%m-%d", time.localtime(now - rule_inactive))

    conn.execute("DELETE FROM domain_traffic_daily WHERE date < ?", (retention_date,))
    conn.execute("DELETE FROM ip_domain_cache WHERE expires < ?", (now - 86400,))

    inactive = conn.execute("""
        SELECT mac, domain FROM domain_traffic_daily
        GROUP BY mac, domain
        HAVING MAX(date) < ?
    """, (inactive_date,)).fetchall()

    for row in inactive:
        mac, domain = row[0], row[1]
        if validate_mac(mac) and validate_domain(domain):
            cmd_remove(mac, domain)

    conn.execute("""
        DELETE FROM domain_traffic_daily WHERE (mac, domain) IN (
            SELECT mac, domain FROM domain_traffic_daily
            GROUP BY mac, domain HAVING MAX(date) < ?
        )
    """, (inactive_date,))

    for (mac,) in conn.execute(
        "SELECT DISTINCT mac FROM domain_traffic_daily"
    ).fetchall():
        if not validate_mac(mac):
            continue
        count = conn.execute(
            "SELECT COUNT(DISTINCT domain) FROM domain_traffic_daily WHERE mac = ?", (mac,)
        ).fetchone()[0]
        if count > max_per_device:
            overflow = conn.execute("""
                SELECT domain FROM domain_traffic_daily
                WHERE mac = ?
                GROUP BY domain
                ORDER BY SUM(bytes_down+bytes_up) DESC
                LIMIT -1 OFFSET ?
            """, (mac, max_per_device)).fetchall()
            for (domain,) in overflow:
                if validate_domain(domain):
                    cmd_remove(mac, domain)
            conn.execute("""
                DELETE FROM domain_traffic_daily WHERE mac = ? AND domain IN (
                    SELECT domain FROM domain_traffic_daily WHERE mac = ?
                    GROUP BY domain
                    ORDER BY SUM(bytes_down+bytes_up) DESC
                    LIMIT -1 OFFSET ?
                )
            """, (mac, mac, max_per_device))

    try:
        result = subprocess.run(["nft", "list", "table"] + NFT_TABLE.split(), capture_output=True, text=True, timeout=10)
        batch = []
        for line in result.stdout.splitlines():
            m = re.search(r'chain (device_domains_([0-9a-f]{12}))\b', line)
            if m:
                chain, mac_clean = m.group(1), m.group(2)
                mac = ':'.join(mac_clean[i:i+2] for i in range(0, 12, 2))
                if not conn.execute(
                    "SELECT 1 FROM domain_traffic_daily WHERE mac = ? LIMIT 1", (mac,)
                ).fetchone():
                    batch.append(f'delete chain {NFT_TABLE} {chain}')
                    print(f"Removing orphaned chain: {chain}", file=sys.stderr)
        if batch:
            execute_nft_batch(batch)
    except Exception as e:
        print(f"Warning during chain cleanup: {e}", file=sys.stderr)

    conn.commit()
    conn.execute("VACUUM")
    print("Cleanup complete", file=sys.stderr)
    return 0


def main():
    if len(sys.argv) < 2:
        print(
            f"Usage: {sys.argv[0]} <init|cleanup|ensure-dispatch|add <mac> <domain> <ip>|remove <mac> <domain>>",
            file=sys.stderr
        )
        return 1

    cmd = sys.argv[1]

    if cmd in ("init", "cleanup", "ensure-dispatch", "add", "remove") and not domain_tracking_enabled():
        return 0

    if cmd in ("init", "cleanup"):
        lock_fd = acquire_lock(cmd)
        if lock_fd is None:
            print(f"domain-manager {cmd} already running, skipping", file=sys.stderr)
            return 0

    if cmd == "ensure-dispatch":
        return cmd_ensure_dispatch()

    if cmd == "add":
        if len(sys.argv) < 5:
            print("Usage: add <mac> <domain> <ip>", file=sys.stderr)
            return 1
        return cmd_add(sys.argv[2], sys.argv[3], sys.argv[4])

    if cmd == "remove":
        if len(sys.argv) < 4:
            print("Usage: remove <mac> <domain>", file=sys.stderr)
            return 1
        return cmd_remove(sys.argv[2], sys.argv[3])

    conn = get_db()
    try:
        if cmd == "init":
            ensure_db_tables(conn)
            return cmd_init(conn)
        elif cmd == "cleanup":
            return cmd_cleanup(conn)
        else:
            print(f"Unknown command: {cmd}", file=sys.stderr)
            return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
