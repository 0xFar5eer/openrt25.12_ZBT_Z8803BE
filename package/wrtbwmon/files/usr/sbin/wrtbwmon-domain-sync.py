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

from wrtbwmon_nft import counter_bytes, domain_chain_to_mac, list_table_json, nft_objects, rule_comment

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
LOCK_FILE = "/var/run/wrtbwmon-domain-sync.lock"
NFT_TABLE = os.environ.get("NFT_TABLE", "inet fw4")
DOMAIN_DISPATCH_MAP = "wrtbwmon_domain_dispatch_v4"

MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')


def acquire_lock():
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o644)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (IOError, OSError):
        return None


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


def get_all_domain_counters():
    """Get all domain counters in a single nft call - much faster than per-chain."""
    counters = {}  # mac -> {domain -> {dl: bytes, ul: bytes}}

    try:
        data, proc = list_table_json(NFT_TABLE, timeout=30)
        if data:
            for rule in nft_objects(data, "rule"):
                mac = domain_chain_to_mac(rule.get("chain"))
                if not mac:
                    continue
                comment = rule_comment(rule)
                if comment.startswith("domain_ul:"):
                    direction = "ul"
                    domain = comment[len("domain_ul:"):]
                elif comment.startswith("domain_dl:"):
                    direction = "dl"
                    domain = comment[len("domain_dl:"):]
                else:
                    continue
                counters.setdefault(mac, {}).setdefault(domain, {"dl": 0, "ul": 0})
                counters[mac][domain][direction] = counter_bytes(rule)
            return counters
        if proc and proc.returncode != 0 and proc.stderr.strip():
            print(f"nft json list table failed: {proc.stderr.strip()}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print("nft json list table timed out", file=sys.stderr)
    except Exception as e:
        print(f"Error getting JSON counters: {e}", file=sys.stderr)

    try:
        # List all device_domains_ chains and their rules in one call
        result = subprocess.run(
            ["nft", "list", "table"] + NFT_TABLE.split(),
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            if result.stderr.strip():
                print(f"nft list table failed: {result.stderr.strip()}", file=sys.stderr)
            return counters

        current_chain = None
        current_mac = None

        for line in result.stdout.splitlines():
            # Detect chain start
            chain_match = re.match(r'\s*chain (device_domains_\w+)', line)
            if chain_match:
                current_chain = chain_match.group(1)
                current_mac = chain_to_mac(current_chain)
                if current_mac and current_mac not in counters:
                    counters[current_mac] = {}
                continue

            # Detect chain end
            if line.strip() == "}" and current_chain:
                current_chain = None
                current_mac = None
                continue

            # Parse counter rules
            if current_mac and "counter" in line:
                # Match: ip daddr @set_name counter packets N bytes M comment "domain_ul:domain"
                ul_match = re.search(r'counter\s+packets\s+\d+\s+bytes\s+(\d+)\s+comment\s+"domain_ul:([^"]+)"', line)
                dl_match = re.search(r'counter\s+packets\s+\d+\s+bytes\s+(\d+)\s+comment\s+"domain_dl:([^"]+)"', line)

                if ul_match:
                    domain = ul_match.group(2)
                    bytes_val = int(ul_match.group(1))
                    if domain not in counters[current_mac]:
                        counters[current_mac][domain] = {"dl": 0, "ul": 0}
                    counters[current_mac][domain]["ul"] = bytes_val
                elif dl_match:
                    domain = dl_match.group(2)
                    bytes_val = int(dl_match.group(1))
                    if domain not in counters[current_mac]:
                        counters[current_mac][domain] = {"dl": 0, "ul": 0}
                    counters[current_mac][domain]["dl"] = bytes_val

    except subprocess.TimeoutExpired:
        print("nft list table timed out", file=sys.stderr)
    except Exception as e:
        print(f"Error getting counters: {e}", file=sys.stderr)

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
    lock_fd = acquire_lock()
    if lock_fd is None:
        return 0

    try:
        conn = get_db()

        today = time.strftime("%Y-%m-%d", time.localtime())

        counters = get_all_domain_counters()

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
