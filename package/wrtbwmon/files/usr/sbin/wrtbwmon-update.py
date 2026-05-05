#!/usr/bin/env python3
"""Fast device traffic updater — Python rewrite.

Replaces the wrtbwmon update shell function.

Before: ~130 subprocess spawns/minute (6 per device × N devices + nft per-chain calls)
After:  3 subprocess calls total regardless of device count:
  1. nft list table   — read all device chains + counters at once
  2. ip neigh show    — ARP table (once, batch)
  3. sqlite3          — all device upserts in one transaction
"""

import os
import sys
import sqlite3
import subprocess
import time
import re
import fcntl

from wrtbwmon_nft import chain_to_ipv4, counter_bytes, list_table_json, nft_objects, rule_comment

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
NFT_TABLE = os.environ.get("NFT_TABLE", "inet fw4")
LOCK_FILE = "/var/run/wrtbwmon-update.lock"
DEFAULT_IFACE = "br-lan"

MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
IP4_RE = re.compile(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
IP6_RE = re.compile(r'^[0-9a-fA-F:]+$')


def validate_mac(mac):
    return bool(mac and MAC_RE.match(mac))


def validate_ip4(ip):
    if not ip or not IP4_RE.match(ip):
        return False
    return all(0 <= int(o) <= 255 for o in ip.split('.'))


def acquire_lock():
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_WRONLY)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (IOError, OSError):
        return None


def parse_nft_table():
    """Read the entire nft table once and extract:
    - existing device chains (ip → chain_name)
    - per-device upload/download byte counters
    - dispatch map entries (ip → chain)

    Returns: (counters, map_keys, chains)
    - counters: {ip: {up: bytes, down: bytes}}
    - map_keys: {ip: chain_name}  (v4 dispatch map)
    - chains: set of chain names
    """
    counters = {}
    map_keys = {}
    chains = set()

    try:
        data, proc = list_table_json(NFT_TABLE, timeout=15)
        if data:
            for chain in nft_objects(data, "chain"):
                name = chain.get("name")
                if not name or not name.startswith("device_"):
                    continue
                chains.add(name)
                ip = chain_to_ipv4(name)
                if ip:
                    counters.setdefault(ip, {"up": 0, "down": 0, "has_rules": False})
            for map_obj in nft_objects(data, "map"):
                if map_obj.get("name") != "wrtbwmon_dispatch_v4":
                    continue
                for elem in map_obj.get("elem", []) or []:
                    if isinstance(elem, list) and len(elem) == 2:
                        target = elem[1].get("jump", {}).get("target") if isinstance(elem[1], dict) else None
                        if target:
                            map_keys[elem[0]] = target
            for rule in nft_objects(data, "rule"):
                ip = chain_to_ipv4(rule.get("chain"))
                if not ip:
                    continue
                comment = rule_comment(rule)
                if comment not in ("upload", "download"):
                    continue
                direction = "up" if comment == "upload" else "down"
                counters.setdefault(ip, {"up": 0, "down": 0, "has_rules": False})
                counters[ip][direction] = counter_bytes(rule)
                counters[ip]["has_rules"] = True
            return counters, map_keys, chains
        if proc and proc.returncode != 0 and proc.stderr.strip():
            print(f"nft json list table failed: {proc.stderr.strip()}", file=sys.stderr)
    except Exception as e:
        print(f"nft json parse failed: {e}", file=sys.stderr)

    try:
        result = subprocess.run(
            ["nft", "list", "table"] + NFT_TABLE.split(),
            capture_output=True, text=True, timeout=15
        )
        text = result.stdout
    except Exception as e:
        print(f"nft list table failed: {e}", file=sys.stderr)
        return counters, map_keys, chains

    current_chain = None
    in_v4_map = False

    for line in text.splitlines():
        s = line.strip()

        m = re.match(r'chain (device_\S+)\s*\{', s)
        if m:
            current_chain = m.group(1)
            chains.add(current_chain)
            ip = _chain_to_ip(current_chain)
            if ip:
                counters.setdefault(ip, {"up": 0, "down": 0, "has_rules": False})
            continue

        if s == '}':
            current_chain = None
            in_v4_map = False
            continue

        if 'map wrtbwmon_dispatch_v4' in s:
            in_v4_map = True
            continue

        if in_v4_map:
            m = re.search(r'(\d+\.\d+\.\d+\.\d+)\s*:\s*jump\s+(\S+)', s)
            if m:
                map_keys[m.group(1)] = m.group(2)
            continue

        if current_chain:
            ip = _chain_to_ip(current_chain)
            if not ip:
                continue
            m = re.search(r'bytes (\d+).*comment "(upload|download)"', s)
            if m:
                direction = "up" if m.group(2) == "upload" else "down"
                counters.setdefault(ip, {"up": 0, "down": 0, "has_rules": False})
                counters[ip][direction] = int(m.group(1))
                counters[ip]["has_rules"] = True

    return counters, map_keys, chains


def _chain_to_ip(chain_name):
    """Convert 'device_192_168_1_25' → '192.168.1.25'."""
    m = re.match(r'device_(\d+)_(\d+)_(\d+)_(\d+)$', chain_name)
    if m:
        ip = f"{m.group(1)}.{m.group(2)}.{m.group(3)}.{m.group(4)}"
        if validate_ip4(ip):
            return ip
    return None


def _ip_to_chain(ip):
    return "device_" + ip.replace(".", "_")


def get_arp_table():
    """Read ARP table once, deduplicated by MAC.

    When a device has multiple IPs (e.g. DHCP renewal changed IP but stale
    ARP entry remains), prefer the DHCP lease IP, then REACHABLE/active ARP
    entries over STALE ones.

    Returns {ip: (mac, iface)} with at most one entry per MAC.
    """
    # Phase 1: read DHCP leases for canonical mac→ip
    lease_ips = {}  # mac → ip
    try:
        with open("/tmp/dhcp.leases") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 4:
                    mac, ip = parts[1].lower(), parts[2]
                    if validate_mac(mac) and validate_ip4(ip):
                        lease_ips[mac] = ip
    except Exception:
        pass

    # Phase 2: read ARP table, track state per entry
    arp_entries = []  # [(ip, mac, iface, is_reachable)]
    try:
        r = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[3] == "lladdr":
                ip, iface, mac = parts[0], parts[2], parts[4].lower()
                if validate_ip4(ip) and validate_mac(mac):
                    is_reachable = "REACHABLE" in line or "DELAY" in line
                    arp_entries.append((ip, mac, iface, is_reachable))
    except Exception:
        pass

    # Phase 3: pick best IP per MAC
    #   Priority: DHCP lease > REACHABLE ARP > STALE ARP
    mac_best = {}  # mac → (ip, iface, priority)
    for ip, mac, iface, is_reachable in arp_entries:
        priority = 2 if ip == lease_ips.get(mac) else (1 if is_reachable else 0)
        prev = mac_best.get(mac)
        if prev is None or priority > prev[2]:
            mac_best[mac] = (ip, iface, priority)

    # For MACs in DHCP leases but with only STALE ARP, force the lease IP
    for mac, lease_ip in lease_ips.items():
        if mac in mac_best and mac_best[mac][0] != lease_ip:
            # Only override if we have an ARP entry for this MAC at all
            _, iface, _ = mac_best[mac]
            mac_best[mac] = (lease_ip, iface, 2)

    result = {}
    for mac, (ip, iface, _) in mac_best.items():
        result[ip] = (mac, iface)
    return result


def get_hostnames():
    """Read hostnames from UCI (static) and DHCP leases.
    Returns {mac: hostname}. Never does DNS lookups.
    """
    hostnames = {}

    # UCI static DHCP assignments
    try:
        r = subprocess.run(["uci", "show", "dhcp"], capture_output=True, text=True, timeout=3)
        entries = {}
        for line in r.stdout.splitlines():
            m = re.match(r"dhcp\.(@host\[\d+\]|\w+)\.(mac|name)='([^']+)'", line)
            if m:
                key, field, val = m.group(1), m.group(2), m.group(3)
                entries.setdefault(key, {})[field] = val
        for entry in entries.values():
            mac = entry.get("mac", "").lower()
            name = entry.get("name", "")
            if mac and name and validate_mac(mac):
                hostnames[mac] = name
    except Exception:
        pass

    # DHCP leases file
    leases_path = "/tmp/dhcp.leases"
    if os.path.exists(leases_path):
        try:
            with open(leases_path) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 4:
                        mac, name = parts[1].lower(), parts[3]
                        if validate_mac(mac) and name and name != "*":
                            hostnames.setdefault(mac, name)
        except Exception:
            pass

    return hostnames


def ensure_device_chains(arp_table, map_keys, chains, counters):
    """Create, repair, and clean up nft chains for devices. Single batch call."""
    batch = []
    active_ips = set(arp_table.keys())

    for ip, (mac, iface) in arp_table.items():
        chain_name = _ip_to_chain(ip)
        has_rules = counters.get(ip, {}).get("has_rules", False)
        if chain_name not in chains:
            batch += [
                f'add chain {NFT_TABLE} {chain_name}',
                f'add rule {NFT_TABLE} {chain_name} ip saddr {ip} counter comment "upload"',
                f'add rule {NFT_TABLE} {chain_name} ip daddr {ip} counter comment "download"',
            ]
        elif not has_rules:
            batch += [
                f'add rule {NFT_TABLE} {chain_name} ip saddr {ip} counter comment "upload"',
                f'add rule {NFT_TABLE} {chain_name} ip daddr {ip} counter comment "download"',
            ]
        if ip not in map_keys:
            batch.append(
                f'add element {NFT_TABLE} wrtbwmon_dispatch_v4 '
                f'{{ {ip} : jump {chain_name} }}'
            )

    # Clean orphaned map entries: IPs in dispatch map but not in ARP
    # (device changed IP via DHCP renewal)
    orphaned_ips = set()
    for map_ip in map_keys:
        if map_ip not in active_ips:
            orphaned_ips.add(map_ip)

    for oip in orphaned_ips:
        batch.append(f'delete element {NFT_TABLE} wrtbwmon_dispatch_v4 {{ {oip} }}')

    if batch:
        try:
            proc = subprocess.run(
                ["nft", "-f", "-"],
                input="\n".join(batch) + "\n",
                capture_output=True, text=True, timeout=15
            )
            if proc.returncode != 0 and proc.stderr:
                for line in proc.stderr.splitlines():
                    if "already exists" not in line and line.strip():
                        print(f"nft: {line}", file=sys.stderr)
        except Exception as e:
            print(f"nft batch error: {e}", file=sys.stderr)


def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-1000")
    return conn


def load_previous_counters(conn):
    """Load most recent traffic_daily row per device for delta computation.
    Returns {mac: {last_counter_down, last_counter_up, bytes_down, bytes_up, date}}.
    """
    result = {}
    try:
        rows = conn.execute("""
            SELECT d.mac, td.last_counter_down, td.last_counter_up,
                   td.bytes_down, td.bytes_up, td.date
            FROM traffic_daily td
            JOIN devices d ON td.device_id = d.id
            WHERE td.date = (
                SELECT MAX(t2.date) FROM traffic_daily t2
                WHERE t2.device_id = td.device_id
            )
        """).fetchall()
        for row in rows:
            result[row["mac"].lower()] = {
                "last_counter_down": row["last_counter_down"] or 0,
                "last_counter_up":   row["last_counter_up"]   or 0,
                "bytes_down":        row["bytes_down"]        or 0,
                "bytes_up":          row["bytes_up"]          or 0,
                "date":              row["date"],
            }
    except Exception as e:
        print(f"Error loading previous counters: {e}", file=sys.stderr)
    return result


def compute_delta(current, prev):
    """Traffic delta with counter-reset detection."""
    if prev is None:
        return current
    if current < prev:
        return current  # counter reset (reboot / fw4 reload)
    return current - prev


def update_traffic(conn, now, today, arp_table, counters, hostnames, prev_counters):
    """Upsert traffic_daily (one row per device per day) in one transaction."""
    if not counters:
        return

    updated = 0
    try:
        conn.execute("BEGIN IMMEDIATE")

        for ip, nft in counters.items():
            if ip not in arp_table:
                continue
            mac, _iface = arp_table[ip]
            if not validate_mac(mac):
                continue

            down_bytes = nft.get("down", 0)
            up_bytes   = nft.get("up",   0)
            hostname   = hostnames.get(mac)

            prev = prev_counters.get(mac)
            if prev:
                dl_delta = compute_delta(down_bytes, prev["last_counter_down"])
                ul_delta = compute_delta(up_bytes,   prev["last_counter_up"])
                if prev["date"] == today:
                    new_down = prev["bytes_down"] + dl_delta
                    new_up   = prev["bytes_up"]   + ul_delta
                else:
                    new_down = dl_delta   # new day — start fresh
                    new_up   = ul_delta
            else:
                # First time seeing this device — no previous counter to diff against.
                # Start from 0 so we don't inflate day-1 with historical nft counter.
                dl_delta = 0
                ul_delta = 0
                new_down = 0
                new_up   = 0

            last_seen = now if (dl_delta > 0 or ul_delta > 0) else None

            conn.execute("""
                INSERT INTO devices (mac, ip, hostname, first_seen, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(mac) DO UPDATE SET
                    ip         = ?,
                    hostname   = COALESCE(?, hostname),
                    updated_at = ?
            """, (mac, ip, hostname, now, now, ip, hostname, now))

            conn.execute("""
                INSERT INTO traffic_daily
                    (device_id, date, bytes_down, bytes_up, last_seen,
                     last_counter_down, last_counter_up)
                SELECT d.id, ?, ?, ?, ?, ?, ?
                FROM devices d WHERE d.mac = ?
                ON CONFLICT(device_id, date) DO UPDATE SET
                    bytes_down        = excluded.bytes_down,
                    bytes_up          = excluded.bytes_up,
                    last_seen         = CASE WHEN excluded.last_seen IS NOT NULL
                                             THEN excluded.last_seen ELSE last_seen END,
                    last_counter_down = excluded.last_counter_down,
                    last_counter_up   = excluded.last_counter_up
            """, (today, new_down, new_up, last_seen, down_bytes, up_bytes, mac))
            updated += 1

        conn.commit()
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        print(f"DB update error: {e}", file=sys.stderr)
        return

    print(f"Updated {updated} devices for {today}", file=sys.stderr)


def main():
    if not os.path.exists(DB_FILE):
        print(f"Database not found: {DB_FILE}", file=sys.stderr)
        return 1

    lock_fd = acquire_lock()
    if lock_fd is None:
        print("Update already running, skipping", file=sys.stderr)
        return 0

    try:
        now = int(time.time())

        counters, map_keys, chains = parse_nft_table()
        arp_table = get_arp_table()
        hostnames = get_hostnames()

        # Create device chains for ARP-visible devices (bootstrap after reboot)
        ensure_device_chains(arp_table, map_keys, chains, counters)

        if not counters:
            # After ensure_device_chains, re-read nft state to pick up newly created chains
            counters, map_keys, chains = parse_nft_table()

        if not counters:
            print("No device chains found in nft table", file=sys.stderr)
            return 0

        today = time.strftime("%Y-%m-%d", time.localtime(now))

        conn = get_db()
        try:
            prev_counters = load_previous_counters(conn)
            update_traffic(conn, now, today, arp_table, counters, hostnames, prev_counters)
        finally:
            conn.close()

        return 0

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    finally:
        try:
            os.close(lock_fd)
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
