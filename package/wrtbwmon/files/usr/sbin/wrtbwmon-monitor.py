#!/usr/bin/env python3
"""wrtbwmon-monitor — per-minute monitor (runs at cron +30s).

Replaces:
  wrtbwmon-speed-tracker.sh   (speed tracking via nft counters)
  wrtbwmon-utils.sh monitor-devices  (device chain readiness)
  wrtbwmon-utils.sh migrate-hostnames (hostname resolution, rate-limited)

Speed: reads nft table once, writes /tmp/wrtbwmon-speed.json. No DB I/O on
the fast path. Hostname migration is rate-limited to every 15 minutes via a
stamp file so it never adds latency to normal runs.
"""

import os
import sys
import re
import subprocess
import sqlite3
import time
import json
import fcntl

from wrtbwmon_nft import counter_bytes, nft_objects, rule_comment

DB_FILE = os.environ.get("DB_FILE", "/etc/wrtbwmon/traffic.db")
NFT_TABLE = os.environ.get("NFT_TABLE", "netdev wrtbwmon_acct")
LOCK_FILE = "/var/run/wrtbwmon-monitor.lock"
SPEED_STATE = "/tmp/wrtbwmon-speed.state"
SPEED_JSON  = "/tmp/wrtbwmon-speed.json"
COUNTERS_JSON = "/tmp/wrtbwmon-device-counters.json"
HOSTNAME_STAMP = "/tmp/wrtbwmon-hostname-stamp"
HOSTNAME_INTERVAL = 900  # 15 minutes

MAC_RE = re.compile(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')


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


def _ip_to_chain(ip):
    return "device_" + ip.replace(".", "_")


def read_cached_device_counters(max_age=90):
    try:
        with open(COUNTERS_JSON) as f:
            payload = json.load(f)
        if int(time.time()) - int(payload.get("t", 0)) > max_age:
            return None
        data = payload.get("c", {})
        counters = {}
        for ip, values in data.items():
            counters[ip] = {
                "up": int(values.get("up", 0)),
                "down": int(values.get("down", 0)),
            }
        return counters
    except Exception:
        return None


def get_candidate_ips():
    ips = set()
    try:
        result = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.splitlines():
            parts = line.split()
            if parts and re.match(r'^\d+\.\d+\.\d+\.\d+$', parts[0]):
                ips.add(parts[0])
    except Exception:
        pass
    try:
        with open("/tmp/dhcp.leases") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and re.match(r'^\d+\.\d+\.\d+\.\d+$', parts[2]):
                    ips.add(parts[2])
    except Exception:
        pass
    return sorted(ips)


def read_device_chain(ip):
    chain_name = _ip_to_chain(ip)
    counter = {"up": 0, "down": 0}
    try:
        result = subprocess.run(
            ["nft", "-j", "list", "chain"] + NFT_TABLE.split() + [chain_name],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return None
        try:
            data = json.loads(result.stdout)
            for rule in nft_objects(data, "rule"):
                comment = rule_comment(rule)
                if comment not in ("upload", "download"):
                    continue
                direction = "up" if comment == "upload" else "down"
                counter[direction] = counter_bytes(rule)
            return counter
        except json.JSONDecodeError:
            pass
    except Exception:
        return None

    try:
        result = subprocess.run(
            ["nft", "list", "chain"] + NFT_TABLE.split() + [chain_name],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            m = re.search(r'bytes (\d+).*comment "(upload|download)"', line)
            if m:
                direction = "up" if m.group(2) == "upload" else "down"
                counter[direction] = int(m.group(1))
        return counter
    except Exception:
        return None


def read_nft_device_counters():
    counters = {}
    cached = read_cached_device_counters()
    if cached is not None:
        return cached

    for ip in get_candidate_ips():
        chain_counter = read_device_chain(ip)
        if chain_counter is not None:
            counters[ip] = chain_counter
    return counters


def track_speed(counters):
    """Compute bytes/sec from nft counter deltas, write JSON."""
    now = int(time.time())

    prev_state = {}
    prev_time = 0
    if os.path.exists(SPEED_STATE):
        try:
            with open(SPEED_STATE) as f:
                d = json.load(f)
                prev_time = d.get("t", 0)
                prev_state = d.get("c", {})
        except Exception:
            pass

    total_down = 0
    total_up = 0
    time_diff = now - prev_time

    if 5 <= time_diff <= 120 and prev_state:
        for ip, c in counters.items():
            p = prev_state.get(ip, {"up": 0, "down": 0})
            d_down = c["down"] - p.get("down", 0)
            d_up   = c["up"]   - p.get("up",   0)
            if d_down < 0: d_down = c["down"]
            if d_up   < 0: d_up   = c["up"]
            total_down += max(0, d_down // time_diff)
            total_up   += max(0, d_up   // time_diff)

    speed = {
        "download_speed": total_down,
        "upload_speed":   total_up,
        "total_speed":    total_down + total_up,
        "last_update":    now,
    }
    def _atomic_write(path, data):
        tmp = path + ".tmp"
        try:
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, path)
        except Exception:
            try:
                os.unlink(tmp)
            except Exception:
                pass

    _atomic_write(SPEED_JSON, speed)
    _atomic_write(SPEED_STATE, {"t": now, "c": {ip: c for ip, c in counters.items()}})


def get_hostnames_from_system():
    """Batch-read hostnames from UCI and DHCP leases. Returns {mac: hostname}."""
    hostnames = {}

    try:
        r = subprocess.run(["uci", "show", "dhcp"], capture_output=True, text=True, timeout=3)
        entries = {}
        for line in r.stdout.splitlines():
            m = re.match(r"dhcp\.(@host\[\d+\]|\w+)\.(mac|name)='([^']+)'", line)
            if m:
                key, field, val = m.group(1), m.group(2), m.group(3)
                entries.setdefault(key, {})[field] = val
        for e in entries.values():
            mac = e.get("mac", "").lower()
            name = e.get("name", "")
            if mac and name and MAC_RE.match(mac):
                hostnames[mac] = name
    except Exception:
        pass

    if os.path.exists("/tmp/dhcp.leases"):
        try:
            with open("/tmp/dhcp.leases") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 4:
                        mac, name = parts[1].lower(), parts[3]
                        if MAC_RE.match(mac) and name and name != "*":
                            hostnames.setdefault(mac, name)
        except Exception:
            pass

    return hostnames


def should_run_hostname_migration():
    try:
        with open(HOSTNAME_STAMP) as f:
            last = int(f.read().strip())
        return int(time.time()) - last >= HOSTNAME_INTERVAL
    except Exception:
        return True


def migrate_hostnames(conn):
    """Update hostname for devices without one. Rate-limited to every 15 min."""
    if not should_run_hostname_migration():
        return

    hostnames = get_hostnames_from_system()
    if not hostnames:
        return

    try:
        devices = conn.execute(
            "SELECT mac FROM devices WHERE hostname IS NULL OR hostname = ''"
        ).fetchall()
        updated = 0
        conn.execute("BEGIN")
        for (mac,) in devices:
            hn = hostnames.get(mac.lower())
            if hn:
                conn.execute(
                    "UPDATE devices SET hostname = ?, updated_at = ? WHERE mac = ?",
                    (hn, int(time.time()), mac)
                )
                updated += 1
        conn.execute("COMMIT")
        if updated:
            print(f"Migrated hostnames for {updated} devices", file=sys.stderr)
    except Exception as e:
        try: conn.execute("ROLLBACK")
        except Exception: pass
        print(f"Hostname migration error: {e}", file=sys.stderr)

    try:
        with open(HOSTNAME_STAMP, "w") as f:
            f.write(str(int(time.time())))
    except Exception:
        pass


def main():
    if not monitoring_enabled():
        return 0

    lock_fd = acquire_lock()
    if lock_fd is None:
        return 0

    try:
        counters = read_nft_device_counters()
        track_speed(counters)

        if os.path.exists(DB_FILE):
            conn = sqlite3.connect(DB_FILE, timeout=30)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA busy_timeout=10000")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute("PRAGMA cache_size=-1000")
            try:
                migrate_hostnames(conn)
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
