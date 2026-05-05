#!/usr/bin/env python3
"""Fast DNS interceptor for domain tracking - Python rewrite for parallel execution.
Replaces wrtbwmon-dns-interceptor-unified.sh for ~10x speedup.
"""

import os
import sys
import sqlite3
import subprocess
import time
import re
import fcntl
import socket
import tempfile
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
CACHE_EXPIRY = int(os.environ.get("DOMAIN_CACHE_TTL", "604800"))    # 7 days — keeps CDN IP cache stable for long-term device/domain history
MAX_DOMAINS_PER_CYCLE = 50  # Limit domains processed per cycle
LOCK_FILE = "/var/run/wrtbwmon-dns-interceptor.lock"
NFT_TABLE = os.environ.get("NFT_TABLE", "inet fw4")
DNS_BACKEND = os.environ.get("DNS_BACKEND", "auto")
BACKEND_STAMP = "/tmp/wrtbwmon-dns-backend"
BACKEND_TTL   = 600  # re-detect every 10 minutes

# MAC validation regex
MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
# Domain validation regex
DOMAIN_RE = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$')
# IP validation regex
IP_RE = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')


def validate_mac(mac):
    return bool(MAC_RE.match(mac)) if mac else False

def validate_domain(domain):
    return bool(DOMAIN_RE.match(domain)) if domain else False

def validate_ip(ip):
    if not ip or not IP_RE.match(ip):
        return False
    parts = ip.split('.')
    return all(0 <= int(p) <= 255 for p in parts)

def sql_escape(s):
    return s.replace("'", "''") if s else ""

def mac_to_chain(mac):
    return f"device_domains_{mac.replace(':', '')}"

def domain_to_set(mac, domain):
    clean_domain = re.sub(r'[.\-]', '_', domain)
    clean_domain = re.sub(r'[^a-zA-Z0-9_]', '', clean_domain)
    clean_mac = mac.replace(':', '')
    return f"d_{clean_mac}_{clean_domain}"


def acquire_lock():
    """Acquire file lock to prevent concurrent runs."""
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o644)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (IOError, OSError):
        return None


def get_db():
    """Get database connection with WAL mode for concurrent reads."""
    conn = sqlite3.connect(DB_FILE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-1000")
    return conn


def detect_dns_backend():
    """Detect which DNS backend is available.
    Result cached in BACKEND_STAMP for BACKEND_TTL seconds to avoid
    running urlopen/pgrep on every 60-second invocation.
    """
    if DNS_BACKEND in ("adguard", "dnsmasq"):
        return DNS_BACKEND

    now = int(time.time())
    try:
        with open(BACKEND_STAMP) as f:
            parts = f.read().strip().split(":")
            if len(parts) == 2 and now - int(parts[1]) < BACKEND_TTL:
                return parts[0] or None
    except Exception:
        pass

    # Probe AdGuard Home
    # Only use AGH backend if it sees real client IPs.
    # When DNS is Client→dnsmasq→AGH, AGH only sees 127.0.0.1
    # and cannot provide per-device domain tracking — use dnsmasq instead.
    backend = None
    try:
        req = urllib.request.urlopen("http://127.0.0.1:3000/", timeout=2)
        if req.getcode() == 200:
            # Verify AGH has real client IPs (not just loopback from dnsmasq)
            qreq = urllib.request.urlopen(
                "http://127.0.0.1:3000/control/querylog?limit=20", timeout=3)
            qdata = json.loads(qreq.read().decode())
            real_clients = [e.get("client","") for e in qdata.get("data",[])
                            if e.get("client","") not in ("", "127.0.0.1", "::1")]
            if real_clients:
                backend = "adguard"
            # else: AGH is behind dnsmasq — fall through to dnsmasq backend
    except Exception:
        pass

    # Probe dnsmasq
    if backend is None:
        if os.path.exists("/var/log/dnsmasq.log") or os.path.exists("/tmp/dnsmasq.log"):
            backend = "dnsmasq"
        else:
            try:
                r = subprocess.run(["pgrep", "-f", "dnsmasq"], capture_output=True, timeout=2)
                if r.returncode == 0:
                    backend = "dnsmasq"
            except Exception:
                pass

    try:
        with open(BACKEND_STAMP, "w") as f:
            f.write(f"{backend or ''}:{now}")
    except Exception:
        pass

    return backend


def parse_adguard_logs():
    """Parse AdGuard Home query log for DNS queries."""
    mappings = []  # (ip, domain, timestamp)
    queries = []   # (client_ip, mac, domain, timestamp)

    try:
        url = "http://127.0.0.1:3000/control/querylog?search=&limit=200"
        req = urllib.request.urlopen(url, timeout=5)
        data = json.loads(req.read().decode())

        now = int(time.time())
        for entry in data.get("data", [])[:100]:
            question = entry.get("question", {})
            domain = question.get("name", "").rstrip(".")
            if not domain or not validate_domain(domain):
                continue

            client_ip = entry.get("client", "")
            client_info = entry.get("clientInfo", {})
            mac = client_info.get("mac", "")

            # Try to get MAC from ARP if not in clientInfo
            if not validate_mac(mac) and validate_ip(client_ip):
                mac = get_mac_from_arp(client_ip)

            if validate_mac(mac) and validate_domain(domain):
                queries.append((client_ip, mac.lower(), domain, now))
                # Also store IP→domain mapping
                answers = entry.get("answers", [])
                for ans in answers[:3]:
                    ans_ip = ans.get("address", "")
                    if validate_ip(ans_ip):
                        mappings.append((ans_ip, domain, now))
    except Exception as e:
        print(f"AdGuard parse error: {e}", file=sys.stderr)

    return queries, mappings


def parse_dnsmasq_logs():
    """Parse dnsmasq log for DNS queries and IP mappings via logread."""
    mappings = []
    queries = []
    now = int(time.time())
    seen_queries = set()
    seen_mappings = set()

    # Cache ARP table once (avoids N+1 subprocess calls per query line)
    arp_cache = {}
    try:
        arp_result = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5)
        for line in arp_result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and ":" in parts[4]:
                arp_cache[parts[0]] = parts[4].lower()
    except Exception:
        pass

    # On OpenWrt, dnsmasq logs to syslog (logread), not files
    try:
        result = subprocess.run(
            ["logread", "-e", "dnsmasq"],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            # Parse query lines: "query[A] example.com from 192.168.1.100"
            m = re.match(r'.*query\[\w+\]\s+(\S+)\s+from\s+(\S+)', line)
            if m:
                domain = m.group(1).rstrip(".")
                client_ip = m.group(2)
                # Skip PTR/reverse DNS queries — no forward IPs to track
                if domain.endswith('.in-addr.arpa') or domain.endswith('.ip6.arpa'):
                    continue
                key = (client_ip, domain)
                if key not in seen_queries:
                    seen_queries.add(key)
                    mac = arp_cache.get(client_ip, "")
                    if validate_domain(domain) and validate_mac(mac):
                        queries.append((client_ip, mac.lower(), domain, now))
                continue

            # Parse reply/cached lines: "cached example.com is 1.2.3.4" or "reply example.com is 1.2.3.4"
            m = re.match(r'.*(?:reply|cached)\s+(\S+)\s+is\s+(\S+)', line)
            if m:
                domain = m.group(1).rstrip(".")
                ip = m.group(2)
                key = (ip, domain)
                if key not in seen_mappings and validate_ip(ip) and validate_domain(domain) and ip != "0.0.0.0":
                    seen_mappings.add(key)
                    mappings.append((ip, domain, now))
    except Exception as e:
        print(f"logread error: {e}", file=sys.stderr)

    # Also try log files as fallback
    log_files = ["/var/log/dnsmasq.log", "/tmp/dnsmasq.log"]
    for log_file in log_files:
        if not os.path.exists(log_file):
            continue
        try:
            with open(log_file, 'r') as f:
                for line in f:
                    m = re.match(r'.*query\[\w+\]\s+(\S+)\s+from\s+(\S+)', line)
                    if m:
                        domain = m.group(1).rstrip(".")
                        client_ip = m.group(2)
                        key = (client_ip, domain)
                        if key not in seen_queries:
                            seen_queries.add(key)
                            mac = arp_cache.get(client_ip, "")
                            if validate_domain(domain) and validate_mac(mac):
                                queries.append((client_ip, mac.lower(), domain, now))
                        continue
                    m = re.match(r'.*(?:reply|cached)\s+(\S+)\s+is\s+(\S+)', line)
                    if m:
                        domain = m.group(1).rstrip(".")
                        ip = m.group(2)
                        key = (ip, domain)
                        if key not in seen_mappings and validate_ip(ip) and validate_domain(domain) and ip != "0.0.0.0":
                            seen_mappings.add(key)
                            mappings.append((ip, domain, now))
        except:
            pass

    return queries, mappings


def get_mac_from_arp(ip):
    """Look up MAC address from ARP table."""
    try:
        result = subprocess.run(["ip", "neigh", "show", ip], capture_output=True, text=True, timeout=2)
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and ":" in parts[4]:
                return parts[4].lower()
    except Exception:
        pass
    return ""


def store_mappings(conn, mappings):
    """Store IP→domain mappings in database cache."""
    if not mappings:
        return

    now = int(time.time())
    expires = now + CACHE_EXPIRY

    cursor = conn.cursor()
    for ip, domain, _ in mappings:
        if not validate_ip(ip) or not validate_domain(domain):
            continue
        try:
            cursor.execute(
                "INSERT OR REPLACE INTO ip_domain_cache (ip, domain, expires) VALUES (?, ?, ?)",
                (ip, domain, expires)
            )
        except:
            pass
    conn.commit()


def get_cached_ips(conn, domain):
    """Get cached IPs for a domain."""
    now = int(time.time())
    try:
        cursor = conn.execute(
            "SELECT DISTINCT ip FROM ip_domain_cache WHERE domain=? AND expires > ? LIMIT 10",
            (domain, now)
        )
        return [row[0] for row in cursor.fetchall() if validate_ip(row[0])]
    except Exception:
        return []


def cache_nft_state():
    """Cache nftables state: sets + existing domain-jump rules (avoids duplicates)."""
    state = {"chains": set(), "sets": set(), "rules": {}, "jumps": set()}
    try:
        result = subprocess.run(["nft", "list", "sets"] + NFT_TABLE.split(), capture_output=True, text=True, timeout=10)
        for m in re.finditer(r'set\s+(\S+)\s*\{', result.stdout):
            state["sets"].add(m.group(1))
    except Exception:
        pass
    # Load existing jumps as ip_chain->domain_chain pairs
    try:
        result = subprocess.run(["nft", "list", "table"] + NFT_TABLE.split(), capture_output=True, text=True, timeout=10)
        cur_ch = None
        for line in result.stdout.splitlines():
            chain_any = re.match(r"\s*chain (\S+)\b", line)
            if chain_any:
                state["chains"].add(chain_any.group(1))
            cm = re.match(r"\s*chain (device_\d+_\d+_\d+_\d+)\b", line)
            if cm:
                cur_ch = cm.group(1)
            elif line.strip() == "}":
                cur_ch = None
            elif cur_ch:
                jm = re.search(r"jump (device_domains_\S+)", line)
                if jm:
                    state["jumps"].add(f"{cur_ch}->{jm.group(1)}")
    except Exception:
        pass
    return state


def generate_nft_batch(conn, queries, nft_state):
    """Generate nftables batch commands for all domains, using cached state."""
    batch_lines = []
    processed = 0

    # Deduplicate queries by (mac, domain)
    seen = set()
    unique_queries = []
    for client_ip, mac, domain, ts in queries:
        key = (mac, domain)
        if key not in seen:
            seen.add(key)
            unique_queries.append((client_ip, mac, domain, ts))

    # Limit domains per cycle
    for client_ip, mac, domain, ts in unique_queries[:MAX_DOMAINS_PER_CYCLE]:
        chain_name = mac_to_chain(mac)
        set_name = domain_to_set(mac, domain)
        dl_set_name = f"{set_name}_dl"

        # Get cached IPs for this domain; resolve live if not cached
        ips = get_cached_ips(conn, domain)
        if not ips:
            try:
                results = socket.getaddrinfo(domain, None, socket.AF_INET, socket.SOCK_STREAM)
                ips = list(set(r[4][0] for r in results
                               if validate_ip(r[4][0]) and r[4][0] != "0.0.0.0"))
                if ips:
                    now_t = int(time.time())
                    for ip in ips:
                        conn.execute(
                            "INSERT OR REPLACE INTO ip_domain_cache (ip,domain,expires) VALUES (?,?,?)",
                            (ip, domain, now_t + CACHE_EXPIRY))
                    conn.commit()
            except Exception:
                pass
        if not ips:
            continue

        # Create device_domains chain + jump from device IP chain (if not already wired)
        if chain_name not in nft_state["chains"]:
            batch_lines.append(f'add chain {NFT_TABLE} {chain_name}')
            nft_state["chains"].add(chain_name)
        ip_chain = "device_" + client_ip.replace(".", "_")
        jump_key = f"{ip_chain}->{chain_name}"
        if jump_key not in nft_state["jumps"]:
            batch_lines.append(f'add rule {NFT_TABLE} {ip_chain} jump {chain_name}')
            nft_state["jumps"].add(jump_key)

        # Create sets if not exists
        if set_name not in nft_state["sets"]:
            batch_lines.append(f'add set {NFT_TABLE} {set_name} {{ type ipv4_addr; flags interval; comment "{domain}" ; }}')
            nft_state["sets"].add(set_name)
            # Add upload rule
            batch_lines.append(f'add rule {NFT_TABLE} {chain_name} ip daddr @{set_name} counter comment "domain_ul:{domain}"')

        if dl_set_name not in nft_state["sets"]:
            batch_lines.append(f'add set {NFT_TABLE} {dl_set_name} {{ type ipv4_addr; flags interval; comment "{domain}" ; }}')
            nft_state["sets"].add(dl_set_name)
            # Add download rule
            batch_lines.append(f'add rule {NFT_TABLE} {chain_name} ip saddr @{dl_set_name} counter comment "domain_dl:{domain}"')

        # Add IP elements to both sets
        for ip in ips:
            batch_lines.append(f"add element {NFT_TABLE} {set_name} {{ {ip} }}")
            batch_lines.append(f"add element {NFT_TABLE} {dl_set_name} {{ {ip} }}")

        processed += 1

    return batch_lines, processed


def execute_nft_batch(batch_lines):
    """Execute nft batch commands in a single subprocess."""
    if not batch_lines:
        return True

    try:
        proc = subprocess.run(
            ["nft", "-f", "-"],
            input="\n".join(batch_lines) + "\n",
            capture_output=True,
            text=True,
            timeout=30
        )
        return proc.returncode == 0
    except subprocess.TimeoutExpired:
        print("nft batch timed out", file=sys.stderr)
        return False
    except Exception as e:
        print(f"nft batch error: {e}", file=sys.stderr)
        return False


def refresh_stale_domain_ips(conn, nft_state, max_domains=50):
    """Proactively resolve domains whose ip_domain_cache entries are expired or
    expiring within 1 hour. Updates nft sets with any new IPs.
    This handles CDN IP rotation and OS-level DNS caching where devices reuse
    cached IPs without re-querying dnsmasq — the main cause of low domain coverage.
    """
    now = int(time.time())
    soon = now + CACHE_EXPIRY // 2  # refresh if expiring within half the TTL (~15 min)
    batch_lines = []
    refreshed = 0

    try:
        cursor = conn.execute("""
            SELECT dtd.mac, dtd.domain, COALESCE(MAX(idc.expires), 0) as max_exp
            FROM domain_traffic_daily dtd
            LEFT JOIN ip_domain_cache idc ON dtd.domain = idc.domain
            WHERE dtd.date >= date('now','localtime','-1 day')
            GROUP BY dtd.mac, dtd.domain
            HAVING max_exp < ?
            ORDER BY max_exp ASC
            LIMIT ?
        """, (soon, max_domains))
        stale = cursor.fetchall()
    except Exception as e:
        print(f"Error querying stale domains: {e}", file=sys.stderr)
        return batch_lines

    new_expires = now + CACHE_EXPIRY

    def resolve_domain(args):
        mac, domain = args
        try:
            results = socket.getaddrinfo(domain, None, socket.AF_INET, socket.SOCK_STREAM)
            ips = list(set(r[4][0] for r in results if validate_ip(r[4][0]) and r[4][0] != "0.0.0.0"))
            return mac, domain, ips
        except Exception:
            return mac, domain, []

    # Parallel DNS resolution — reduces N×DNS_latency to max(DNS_latency)
    resolved = {}
    with ThreadPoolExecutor(max_workers=min(8, len(stale) or 1)) as pool:
        futures = {pool.submit(resolve_domain, (mac, domain)): (mac, domain)
                   for mac, domain, _ in stale}
        for future in as_completed(futures, timeout=5):
            try:
                mac, domain, ips = future.result(timeout=1)
                if ips:
                    resolved[(mac, domain)] = ips
            except Exception:
                pass

    for (mac, domain), valid_ips in resolved.items():
        try:
            for ip in valid_ips:
                conn.execute(
                    "INSERT OR REPLACE INTO ip_domain_cache (ip, domain, expires) VALUES (?, ?, ?)",
                    (ip, domain, new_expires)
                )
        except Exception:
            pass

        set_name = domain_to_set(mac, domain)
        dl_set_name = f"{set_name}_dl"
        for ip in valid_ips:
            if set_name in nft_state["sets"]:
                batch_lines.append(f"add element {NFT_TABLE} {set_name} {{ {ip} }}")
            if dl_set_name in nft_state["sets"]:
                batch_lines.append(f"add element {NFT_TABLE} {dl_set_name} {{ {ip} }}")

        refreshed += 1

    if refreshed > 0:
        try:
            conn.commit()
        except Exception:
            pass
        print(f"Refreshed IPs for {refreshed} stale domains")

    return batch_lines


def backfill_cache(conn, queries, nft_state):
    """Backfill cached IPs for new device+domain combinations."""
    now = int(time.time())
    batch_lines = []
    processed = 0

    # Get existing mac+domain pairs with recent traffic
    try:
        cursor = conn.execute(
            "SELECT DISTINCT mac, domain FROM domain_traffic_daily WHERE date >= date('now','localtime','-1 day')"
        )
        existing = set((row[0], row[1]) for row in cursor.fetchall())
    except Exception:
        existing = set()

    # Deduplicate queries
    seen = set()
    for _, mac, domain, _ in queries:
        key = (mac, domain)
        if key in seen:
            continue
        seen.add(key)

        # Skip if already has recent traffic
        if key in existing:
            continue

        chain_name = mac_to_chain(mac)
        set_name = domain_to_set(mac, domain)
        dl_set_name = f"{set_name}_dl"

        ips = get_cached_ips(conn, domain)
        if not ips:
            continue

        if set_name not in nft_state["sets"]:
            batch_lines.append(f'add set {NFT_TABLE} {set_name} {{ type ipv4_addr; flags interval; comment "{domain}" ; }}')
            nft_state["sets"].add(set_name)
            batch_lines.append(f'add rule {NFT_TABLE} {chain_name} ip daddr @{set_name} counter comment "domain_ul:{domain}"')

        if dl_set_name not in nft_state["sets"]:
            batch_lines.append(f'add set {NFT_TABLE} {dl_set_name} {{ type ipv4_addr; flags interval; comment "{domain}" ; }}')
            nft_state["sets"].add(dl_set_name)
            batch_lines.append(f'add rule {NFT_TABLE} {chain_name} ip saddr @{dl_set_name} counter comment "domain_dl:{domain}"')

        for ip in ips:
            batch_lines.append(f"add element {NFT_TABLE} {set_name} {{ {ip} }}")
            batch_lines.append(f"add element {NFT_TABLE} {dl_set_name} {{ {ip} }}")

        processed += 1
        if processed >= MAX_DOMAINS_PER_CYCLE:
            break

    return batch_lines, processed


def main():
    # Acquire lock
    lock_fd = acquire_lock()
    if lock_fd is None:
        return 0  # Already running

    try:
        # Detect DNS backend
        backend = detect_dns_backend()
        if not backend:
            return 0

        # Parse DNS logs
        if backend == "adguard":
            queries, mappings = parse_adguard_logs()
            # Also try dnsmasq for additional query data
            dnsmasq_queries, dnsmasq_mappings = parse_dnsmasq_logs()
            queries.extend(dnsmasq_queries)
            mappings.extend(dnsmasq_mappings)
        else:
            queries, mappings = parse_dnsmasq_logs()

        # Connect to database
        conn = get_db()

        # Cache nftables state once (used by all nft operations)
        nft_state = cache_nft_state()

        # Always refresh stale domain IPs — handles CDN IP rotation and OS DNS caching.
        # This runs every minute regardless of new DNS activity.
        refresh_lines = refresh_stale_domain_ips(conn, nft_state)

        batch_lines = list(refresh_lines)

        if queries or mappings:
            # Store IP→domain mappings
            store_mappings(conn, mappings)

            # Process queries and generate nft batch
            q_lines, processed = generate_nft_batch(conn, queries, nft_state)
            batch_lines.extend(q_lines)

            # Backfill cache
            bf_lines, bf_processed = backfill_cache(conn, queries, nft_state)
            batch_lines.extend(bf_lines)

        # Execute all nft operations in a single call
        if batch_lines:
            execute_nft_batch(batch_lines)

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
