#!/usr/bin/env python3
"""wrtbwmon-cleanup — daily cleanup (runs at 3am via cron).

Replaces:
  wrtbwmon-cleanup-inactive.sh
  wrtbwmon-domain-manager.py cleanup

Inactivity thresholds (env-overridable):
  INACTIVE_DAYS      = 7   (remove domains/devices with no traffic)
  RETENTION_DAYS     = 90  (delete old DB records)
  MAX_DOMAINS_DEVICE = 5000

All nft deletes are batched into one 'nft -f -' call.
DB deletes are one transaction. VACUUM runs at end.
"""

import os
import sys
import re
import subprocess
import sqlite3
import time
import fcntl

DB_FILE    = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
NFT_TABLE  = os.environ.get("NFT_TABLE", "netdev wrtbwmon_acct")
LOCK_FILE  = "/var/run/wrtbwmon-cleanup.lock"

INACTIVE_DAYS    = int(os.environ.get("INACTIVE_DAYS",       7))
RETENTION_DAYS   = int(os.environ.get("RETENTION_DAYS",      90))
MAX_DOMAINS_DEV  = int(os.environ.get("MAX_DOMAINS_DEVICE",  5000))

MAC_RE    = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
DOMAIN_RE = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,252}[a-zA-Z0-9])?$')


def validate_mac(mac):
    return bool(mac and MAC_RE.match(mac))


def validate_domain(d):
    return bool(d and len(d) <= 253 and DOMAIN_RE.match(d))


def domain_to_set(mac, domain):
    mac_clean = mac.replace(":", "")
    dom_clean = re.sub(r"[^a-zA-Z0-9_]", "_", domain)[:200]
    return f"d_{mac_clean}_{dom_clean}"


def acquire_lock():
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_WRONLY)
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


def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-1000")
    return conn


DISPATCH_MAP = "wrtbwmon_domain_dispatch_v4"


def read_nft_state_with_handles():
    """Read nft table with handles for targeted rule deletion.
    Returns:
      chains: set of chain names
      sets:   set of set names
      rules:  {chain: [(handle, comment), ...]}
      dispatch: {domain_chain_name: ip}  — dispatch map reverse lookup
    """
    chains, sets, rules, dispatch = set(), set(), {}, {}
    current_chain = None
    in_dispatch = False

    try:
        r = subprocess.run(
            ["nft", "-a", "list", "table"] + NFT_TABLE.split(),
            capture_output=True, text=True, timeout=20
        )
        for line in r.stdout.splitlines():
            s = line.strip()
            m = re.match(r"chain (\S+)", s)
            if m:
                current_chain = m.group(1)
                in_dispatch = False
                chains.add(current_chain)
                continue
            m = re.match(r"(?:set|map) (\S+)", s)
            if m:
                in_dispatch = (m.group(1) == DISPATCH_MAP)
                sets.add(m.group(1))
                continue
            if s == "}":
                current_chain = None
                in_dispatch = False
                continue
            if in_dispatch:
                m = re.search(r'(\d+\.\d+\.\d+\.\d+)\s*:\s*jump\s+(\S+)', s)
                if m:
                    dispatch[m.group(2).rstrip(',')] = m.group(1)  # chain→ip
                continue
            if current_chain:
                cm = re.search(r'comment "([^"]+)"', s)
                hm = re.search(r'# handle (\d+)', s)
                if cm and hm:
                    rules.setdefault(current_chain, []).append(
                        (hm.group(1), cm.group(1))  # (handle, comment)
                    )
    except Exception as e:
        print(f"nft state read error: {e}", file=sys.stderr)

    return chains, sets, rules, dispatch


def execute_nft_batch(batch):
    if not batch:
        return
    try:
        proc = subprocess.run(
            ["nft", "-f", "-"],
            input="\n".join(batch) + "\n",
            capture_output=True, text=True, timeout=30
        )
        if proc.returncode != 0 and proc.stderr:
            for line in proc.stderr.splitlines():
                if "does not exist" not in line and "no such" not in line.lower() and line.strip():
                    print(f"nft: {line}", file=sys.stderr)
    except Exception as e:
        print(f"nft batch error: {e}", file=sys.stderr)


def cleanup_db_retention(conn, retention_date, now):
    """Delete records older than retention date."""
    conn.execute("DELETE FROM traffic_daily WHERE date < ?", (retention_date,))
    conn.execute("DELETE FROM domain_traffic_daily WHERE date < ?", (retention_date,))
    conn.execute("DELETE FROM ip_domain_cache WHERE expires < ?", (now,))


def get_inactive_devices(conn, inactive_date):
    """Devices with no traffic since inactive_date."""
    return conn.execute("""
        SELECT d.id, d.mac FROM devices d
        WHERE NOT EXISTS (
            SELECT 1 FROM traffic_daily td
            WHERE td.device_id = d.id AND td.date >= ?
        )
    """, (inactive_date,)).fetchall()


def get_inactive_domains(conn, inactive_date):
    """(mac, domain) pairs with no traffic since inactive_date."""
    return conn.execute("""
        SELECT mac, domain FROM domain_traffic_daily
        GROUP BY mac, domain
        HAVING MAX(date) < ?
    """, (inactive_date,)).fetchall()


def get_overflow_domains(conn):
    """(mac, domain) pairs beyond MAX_DOMAINS_DEV per device, ordered by least bytes."""
    result = []
    for (mac,) in conn.execute("SELECT DISTINCT mac FROM domain_traffic_daily").fetchall():
        if not validate_mac(mac):
            continue
        count = conn.execute(
            "SELECT COUNT(DISTINCT domain) FROM domain_traffic_daily WHERE mac = ?", (mac,)
        ).fetchone()[0]
        if count > MAX_DOMAINS_DEV:
            overflow = conn.execute("""
                SELECT domain FROM domain_traffic_daily WHERE mac = ?
                GROUP BY domain
                ORDER BY SUM(bytes_down + bytes_up) ASC
                LIMIT -1 OFFSET ?
            """, (mac, MAX_DOMAINS_DEV)).fetchall()
            for (domain,) in overflow:
                result.append((mac, domain))
    return result


def build_device_nft_removes(mac, chains, sets, dispatch):
    """Build nft delete commands to remove all nft objects for a device.
    Order: remove dispatch entry → flush chain → delete sets → delete chain.
    """
    batch = []
    mac_clean = mac.replace(":", "")
    domain_chain = f"device_domains_{mac_clean}"

    ip = dispatch.get(domain_chain)
    if ip:
        batch.append(f"delete element {NFT_TABLE} {DISPATCH_MAP} {{ {ip} }}")

    if domain_chain in chains:
        batch.append(f"flush chain {NFT_TABLE} {domain_chain}")
    for set_name in sorted(s for s in sets if s.startswith(f"d_{mac_clean}_")):
        batch.append(f"delete set {NFT_TABLE} {set_name}")
    if domain_chain in chains:
        batch.append(f"delete chain {NFT_TABLE} {domain_chain}")
    return batch


def build_domain_nft_removes(mac, domain, chains, sets, rules):
    """Build nft delete commands to remove a single domain's rules and sets.
    Order: delete rules by handle → delete sets (now unreferenced).
    """
    batch = []
    mac_clean = mac.replace(":", "")
    chain_name = f"device_domains_{mac_clean}"
    set_name   = domain_to_set(mac, domain)
    dl_set     = f"{set_name}_dl"

    # Delete rules first (they reference the sets)
    if chain_name in rules:
        for handle, comment in rules[chain_name]:
            if f":{domain}" in comment:
                batch.append(f"delete rule {NFT_TABLE} {chain_name} handle {handle}")

    # Then delete sets (now unreferenced)
    if set_name in sets:
        batch.append(f"delete set {NFT_TABLE} {set_name}")
    if dl_set in sets:
        batch.append(f"delete set {NFT_TABLE} {dl_set}")

    return batch


def cleanup_orphaned_chains(conn, chains, dispatch):
    """Remove device_domains chains that have no corresponding device in DB."""
    # Batch load all known MACs once instead of N queries in loop
    known_macs = {r[0].lower() for r in conn.execute("SELECT mac FROM devices").fetchall()}
    batch = []
    for chain in chains:
        m = re.match(r"device_domains_([0-9a-f]{12})$", chain)
        if not m:
            continue
        mac_clean = m.group(1)
        mac = ":".join(mac_clean[i:i+2] for i in range(0, 12, 2))
        if mac not in known_macs:
            ip = dispatch.get(chain)
            if ip:
                batch.append(f"delete element {NFT_TABLE} {DISPATCH_MAP} {{ {ip} }}")
            batch.append(f"flush chain {NFT_TABLE} {chain}")
            batch.append(f"delete chain {NFT_TABLE} {chain}")
            print(f"Orphaned chain removed: {chain}")
    return batch


def main():
    if not monitoring_enabled():
        return 0

    lock_fd = acquire_lock()
    if lock_fd is None:
        print("Cleanup already running", file=sys.stderr)
        return 0

    try:
        if not os.path.exists(DB_FILE):
            print(f"Database not found: {DB_FILE}", file=sys.stderr)
            return 1

        now = int(time.time())
        today          = time.strftime("%Y-%m-%d", time.localtime(now))
        inactive_date  = time.strftime("%Y-%m-%d", time.localtime(now - INACTIVE_DAYS  * 86400))
        retention_date = time.strftime("%Y-%m-%d", time.localtime(now - RETENTION_DAYS * 86400))

        print(f"Cleanup: inactive<{inactive_date} retention<{retention_date}")

        conn = get_db()
        try:
            chains, sets, rules, dispatch = read_nft_state_with_handles()

            nft_batch = []

            # 1. Remove expired DB records
            cleanup_db_retention(conn, retention_date, now)

            # 2. Inactive devices (no traffic in INACTIVE_DAYS)
            inactive_devices = get_inactive_devices(conn, inactive_date)
            for dev_id, mac in inactive_devices:
                if not validate_mac(mac):
                    continue
                nft_batch += build_device_nft_removes(mac, chains, sets, dispatch)
                conn.execute("DELETE FROM domain_traffic_daily WHERE mac = ?",     (mac,))
                conn.execute("DELETE FROM traffic_daily WHERE device_id = ?",      (dev_id,))
                conn.execute("DELETE FROM devices WHERE id = ?",                   (dev_id,))
                print(f"Removed inactive device: {mac}")

            # 3. Inactive domains (no traffic in INACTIVE_DAYS)
            inactive_domains = get_inactive_domains(conn, inactive_date)
            for mac, domain in inactive_domains:
                if not (validate_mac(mac) and validate_domain(domain)):
                    continue
                nft_batch += build_domain_nft_removes(mac, domain, chains, sets, rules)
                conn.execute(
                    "DELETE FROM domain_traffic_daily WHERE mac = ? AND domain = ?",
                    (mac, domain)
                )

            if inactive_domains:
                print(f"Removed {len(inactive_domains)} inactive domains")

            # 4. Overflow domains (beyond MAX_DOMAINS_DEV)
            overflow = get_overflow_domains(conn)
            for mac, domain in overflow:
                if not (validate_mac(mac) and validate_domain(domain)):
                    continue
                nft_batch += build_domain_nft_removes(mac, domain, chains, sets, rules)
                conn.execute(
                    "DELETE FROM domain_traffic_daily WHERE mac = ? AND domain = ?",
                    (mac, domain)
                )

            # 5. Orphaned nft chains (chain exists but no device in DB)
            nft_batch += cleanup_orphaned_chains(conn, chains, dispatch)

            # Commit DB changes
            try:
                conn.commit()
            except Exception:
                pass

            # Apply nft batch
            execute_nft_batch(nft_batch)

            # VACUUM only when rows were actually deleted (avoids full DB rebuild on idle nights)
            did_work = (
                len(inactive_devices) > 0
                or len(inactive_domains) > 0
                or len(overflow) > 0
                or len(nft_batch) > 0
            )
            if did_work:
                conn.execute("VACUUM")

            print("Cleanup complete")

        finally:
            conn.close()

        return 0

    except Exception as e:
        print(f"Cleanup error: {e}", file=sys.stderr)
        return 1
    finally:
        try:
            os.close(lock_fd)
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
