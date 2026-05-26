#!/usr/bin/env python3
"""Fast domain counter sync - Python rewrite for ~10x speedup.
Replaces 'wrtbwmon-domain-manager.sh sync' for parallel counter collection and batch SQL.
"""

import os
import sys
import sqlite3
import subprocess
import time
import re
import fcntl
import json

from wrtbwmon_nft import counter_bytes, nft_objects, rule_comment

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
LOCK_FILE = "/var/run/wrtbwmon-domain-sync.lock"
NFT_TABLE = os.environ.get("NFT_TABLE", "netdev wrtbwmon_acct")
DOMAIN_DISPATCH_MAP = "wrtbwmon_domain_dispatch_v4"

MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')


def acquire_lock():
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o644)
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


def tracking_enabled():
    return (
        uci_get("wrtbwmon.general.enabled", "0") == "1"
        and uci_get("wrtbwmon.general.domain_tracking", "0") == "1"
    )


def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-1000")
    return conn


def chain_to_mac(chain):
    """Extract MAC from chain name like device_domains_b0de280e23a1."""
    mac_str = chain.replace("device_domains_", "")
    if len(mac_str) != 12:
        return None
    mac = ":".join(mac_str[i:i+2] for i in range(0, 12, 2))
    if MAC_RE.match(mac):
        return mac.lower()
    return None


def get_domain_macs(conn):
    macs = set()
    try:
        cursor = conn.execute("""
            SELECT DISTINCT lower(mac)
            FROM domain_traffic_daily
            WHERE date >= date('now','localtime','-7 day')
            UNION
            SELECT DISTINCT lower(mac)
            FROM devices
            WHERE updated_at >= strftime('%s','now') - 604800
        """)
        for row in cursor.fetchall():
            mac = row[0]
            if mac and MAC_RE.match(mac):
                macs.add(mac)
    except Exception:
        pass
    return sorted(macs)


def mac_to_chain(mac):
    return "device_domains_" + mac.replace(":", "")


def parse_domain_rule(counter, mac, rule):
    comment = rule_comment(rule)
    if comment.startswith("domain_ul:"):
        direction = "ul"
        domain = comment[len("domain_ul:"):]
    elif comment.startswith("domain_dl:"):
        direction = "dl"
        domain = comment[len("domain_dl:"):]
    else:
        return
    counter.setdefault(mac, {}).setdefault(domain, {"dl": 0, "ul": 0})
    counter[mac][domain][direction] = counter_bytes(rule)


def parse_domain_line(counter, mac, line):
    ul_match = re.search(r'counter\s+packets\s+\d+\s+bytes\s+(\d+)\s+comment\s+"domain_ul:([^"]+)"', line)
    dl_match = re.search(r'counter\s+packets\s+\d+\s+bytes\s+(\d+)\s+comment\s+"domain_dl:([^"]+)"', line)
    if ul_match:
        domain = ul_match.group(2)
        counter.setdefault(mac, {}).setdefault(domain, {"dl": 0, "ul": 0})
        counter[mac][domain]["ul"] = int(ul_match.group(1))
    elif dl_match:
        domain = dl_match.group(2)
        counter.setdefault(mac, {}).setdefault(domain, {"dl": 0, "ul": 0})
        counter[mac][domain]["dl"] = int(dl_match.group(1))


def get_all_domain_counters(macs):
    counters = {}  # mac -> {domain -> {dl: bytes, ul: bytes}}

    for mac in macs:
        chain = mac_to_chain(mac)
        try:
            result = subprocess.run(
                ["nft", "-j", "list", "chain"] + NFT_TABLE.split() + [chain],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                continue
            try:
                data = json.loads(result.stdout)
                for rule in nft_objects(data, "rule"):
                    parse_domain_rule(counters, mac, rule)
                continue
            except json.JSONDecodeError:
                pass
        except subprocess.TimeoutExpired:
            print(f"nft json list chain timed out: {chain}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"Error getting JSON counters for {chain}: {e}", file=sys.stderr)
            continue

        try:
            result = subprocess.run(
                ["nft", "list", "chain"] + NFT_TABLE.split() + [chain],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                continue
            for line in result.stdout.splitlines():
                parse_domain_line(counters, mac, line)
        except subprocess.TimeoutExpired:
            print(f"nft list chain timed out: {chain}", file=sys.stderr)
        except Exception as e:
            print(f"Error getting counters for {chain}: {e}", file=sys.stderr)

    return counters


def get_ip_cache(conn):
    """Get all IP→domain mappings in one query."""
    now = int(time.time())
    cache = {}
    try:
        cursor = conn.execute(
            "SELECT domain, ip FROM ip_domain_cache WHERE expires > ?",
            (now,)
        )
        for domain, ip in cursor.fetchall():
            if domain not in cache:
                cache[domain] = ip
    except Exception:
        pass
    return cache


def refresh_dispatch_map(conn):
    """Refresh IP→chain dispatch map using cached ARP data."""
    try:
        # Get current map contents
        result = subprocess.run(
            ["nft", "list", "map"] + NFT_TABLE.split() + [DOMAIN_DISPATCH_MAP],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return
        map_contents = result.stdout

        # Get ARP table once
        arp_result = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5)
        arp_cache = {}
        for line in arp_result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and ":" in parts[4]:
                ip = parts[0]
                mac = parts[4].lower()
                arp_cache[mac] = ip

        # Get all device domain chains
        chain_result = subprocess.run(
            ["nft", "-a", "list", "table"] + NFT_TABLE.split(),
            capture_output=True, text=True, timeout=10
        )
        if chain_result.returncode != 0:
            return

        batch_lines = []
        for m in re.finditer(r'chain (device_domains_\w+)', chain_result.stdout):
            chain = m.group(1)
            mac = chain_to_mac(chain)
            if not mac:
                continue

            ip = arp_cache.get(mac)
            if not ip:
                continue

            # Check if IP is already in map
            if ip not in map_contents:
                batch_lines.append(f"add element {NFT_TABLE} {DOMAIN_DISPATCH_MAP} {{ {ip} : jump {chain} }}")

        if batch_lines:
            proc = subprocess.run(["nft", "-f", "-"], input="\n".join(batch_lines) + "\n",
                                  capture_output=True, text=True, timeout=10)
            if proc.returncode != 0 and proc.stderr.strip():
                print(f"nft dispatch refresh failed: {proc.stderr.strip()}", file=sys.stderr)

    except Exception as e:
        print(f"Error refreshing dispatch map: {e}", file=sys.stderr)


def _delta(current, prev):
    """Counter delta with reset detection."""
    if current < prev:
        return current  # counter reset
    return current - prev


def load_last_state(conn):
    """Load most recent domain_traffic_daily row per (mac, domain) for delta computation.
    Returns {(mac, domain): {last_counter_dl, last_counter_ul, bytes_down, bytes_up, date}}.
    """
    result = {}
    try:
        cursor = conn.execute("""
            SELECT mac, domain, last_counter_dl, last_counter_ul,
                   bytes_down, bytes_up, date
            FROM domain_traffic_daily
            WHERE (mac, domain, date) IN (
                SELECT mac, domain, MAX(date)
                FROM domain_traffic_daily
                GROUP BY mac, domain
            )
        """)
        for row in cursor.fetchall():
            result[(row[0], row[1])] = {
                "last_dl":    row[2] or 0,
                "last_ul":    row[3] or 0,
                "bytes_down": row[4] or 0,
                "bytes_up":   row[5] or 0,
                "date":       row[6],
            }
    except Exception as e:
        print(f"Error reading last counters: {e}", file=sys.stderr)
    return result


def sync_counters_to_db(conn, counters, today):
    """Batch upsert domain_traffic_daily (one row per mac+domain per day)."""
    now = int(time.time())

    last_state = load_last_state(conn)

    params = []
    for mac, domains in counters.items():
        for domain, cd in domains.items():
            dl_bytes = cd["dl"]
            ul_bytes = cd["ul"]

            prev = last_state.get((mac, domain))
            if prev:
                dl_delta = _delta(dl_bytes, prev["last_dl"])
                ul_delta = _delta(ul_bytes, prev["last_ul"])
                if prev["date"] == today:
                    new_down = prev["bytes_down"] + dl_delta
                    new_up   = prev["bytes_up"]   + ul_delta
                else:
                    new_down = dl_delta
                    new_up   = ul_delta
            else:
                dl_delta = dl_bytes
                ul_delta = ul_bytes
                new_down = dl_bytes
                new_up   = ul_bytes

            last_seen = now if (dl_delta > 0 or ul_delta > 0) else None
            params.append((mac, domain, today,
                           new_down, new_up, last_seen,
                           dl_bytes, ul_bytes,
                           new_down, new_up,
                           last_seen, last_seen,  # CASE WHEN ? IS NOT NULL THEN ?
                           dl_bytes, ul_bytes))

    if not params:
        return

    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.executemany("""
            INSERT INTO domain_traffic_daily
                (mac, domain, date, bytes_down, bytes_up, last_seen,
                 last_counter_dl, last_counter_ul)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(mac, domain, date) DO UPDATE SET
                bytes_down      = ?,
                bytes_up        = ?,
                last_seen       = CASE WHEN ? IS NOT NULL THEN ? ELSE last_seen END,
                last_counter_dl = ?,
                last_counter_ul = ?
        """, params)
        conn.execute("COMMIT")
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        print(f"SQL batch error: {e}", file=sys.stderr)


def main():
    if not tracking_enabled():
        return 0

    lock_fd = acquire_lock()
    if lock_fd is None:
        return 0

    try:
        conn = get_db()

        today = time.strftime("%Y-%m-%d", time.localtime())

        macs = get_domain_macs(conn)
        counters = get_all_domain_counters(macs)

        if counters:
            sync_counters_to_db(conn, counters, today)

        conn.close()
        return 0

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    finally:
        try:
            os.close(lock_fd)
        except:
            pass


if __name__ == "__main__":
    sys.exit(main())
