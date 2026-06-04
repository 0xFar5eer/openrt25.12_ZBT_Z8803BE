#!/usr/bin/env python3
"""
wifi-clients-collector.py — MT7996E (WiFi 7 + MLD) version
Collects WiFi client data from configured routers via ubus + iw, outputs JSON.
"""

import subprocess
import json
import re
import time
import sys
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

CONFIG_NAME = "wifi-clients"
DEFAULT_GENERAL = {
    "network_title": "WiFi network",
    "ssh_key": "/root/.ssh/id_dropbear",
    "ssh_connect_timeout": "3",
}
DEFAULT_ROUTERS = [
    {"name": "Local", "host": "localhost", "label": "Local Router", "sort_order": 100},
]
HOST_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+$")
IFACE_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]+$")

SSH_KEY = DEFAULT_GENERAL["ssh_key"]
SSH_OPTS = ["-y", "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=no"]
SSH_CMD = "ssh"

# Cache of our own IPs — computed once at startup to identify the local router
_LOCAL_IPS: set | None = None
# Cache of our own hostname (lowercased, no domain) for hostname-based
# self-detection when DNS resolution of '<host>.lan' fails (dnsmasq has no
# static record for the router itself, AdGuard forwards upstream → NXDOMAIN).
_LOCAL_HOSTNAME: str | None = None


def _uci_value(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
        return value[1:-1].replace("'\\''", "'")
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _as_bool(value: str, default: bool = True) -> bool:
    if value is None:
        return default
    return str(value).lower() in ("1", "true", "yes", "on", "enabled")


def _as_int(value, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _valid_host(value: str) -> bool:
    if value in ("localhost", "127.0.0.1"):
        return True
    if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", value):
        parts = value.split(".")
        if all(0 <= int(part) <= 255 for part in parts):
            return True
        return False
    if value.startswith("-") or value.endswith(".") or ".." in value:
        return False
    labels = value.split(".")
    if any(not label or label.startswith("-") or label.endswith("-") for label in labels):
        return False
    if any(len(label) > 63 for label in labels):
        return False
    if len(value) > 253:
        return False
    return bool(HOST_PATTERN.fullmatch(value or ""))


def _valid_iface(value: str) -> bool:
    if value.startswith("-"):
        return False
    return bool(IFACE_PATTERN.fullmatch(value or ""))


def _valid_path(value: str, default: str) -> str:
    if not value.startswith(("/tmp/", "/var/run/")):
        return default
    if ".." in value or not re.fullmatch(r"[A-Za-z0-9_./-]+", value):
        return default
    return value


def _valid_ssh_key(value: str, default: str) -> str:
    if not value.startswith("/root/.ssh/"):
        return default
    if ".." in value or not re.fullmatch(r"[A-Za-z0-9_./-]+", value):
        return default
    return value


def _valid_timeout(value: int) -> int:
    if value < 1:
        return 1
    if value > 30:
        return 30
    return value


def load_config() -> tuple[dict, list]:
    global SSH_KEY, SSH_OPTS
    general = dict(DEFAULT_GENERAL)
    section_types: dict = {}
    sections: dict = {}

    try:
        result = subprocess.run(
            ["uci", "-q", "show", CONFIG_NAME],
            capture_output=True, text=True, timeout=3
        )
        lines = result.stdout.splitlines() if result.returncode == 0 else []
    except Exception:
        lines = []

    for line in lines:
        if "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        value = _uci_value(raw_value)
        if not key.startswith(CONFIG_NAME + "."):
            continue
        rest = key[len(CONFIG_NAME) + 1:]
        if "." not in rest:
            section_types[rest] = value
            continue
        section, option = rest.split(".", 1)
        sections.setdefault(section, {})[option] = value

    for section, stype in section_types.items():
        if stype == "general":
            general.update(sections.get(section, {}))
            break

    routers = []
    for section, stype in section_types.items():
        if stype != "router":
            continue
        opts = sections.get(section, {})
        if not _as_bool(opts.get("enabled", "1")):
            continue
        host = (opts.get("host") or "").strip()
        if not host or not _valid_host(host):
            continue
        name = (opts.get("name") or section).strip()
        routers.append({
            "name": name,
            "host": host,
            "label": (opts.get("label") or name).strip(),
            "sort_order": _as_int(opts.get("sort_order"), 1000),
        })

    if not routers:
        routers = [dict(router) for router in DEFAULT_ROUTERS]
    routers.sort(key=lambda router: (router.get("sort_order", 1000), router.get("name", "")))

    SSH_KEY = _valid_ssh_key(general.get("ssh_key") or DEFAULT_GENERAL["ssh_key"], DEFAULT_GENERAL["ssh_key"])
    connect_timeout = _valid_timeout(_as_int(general.get("ssh_connect_timeout"), 3))
    SSH_OPTS = ["-y", "-o", f"ConnectTimeout={connect_timeout}", "-o", "StrictHostKeyChecking=no"]

    return general, routers


def ping_check(ip: str) -> bool:
    """Sub-second offline detection. 1 ICMP packet, 1s deadline.

    Much faster than SSH-based reachability (which takes ConnectTimeout seconds
    for offline hosts). Returns True if host responded.
    """
    try:
        r = subprocess.run(
            ["ping", "-c", "1", "-W", "1", ip],
            capture_output=True, timeout=2
        )
        return r.returncode == 0
    except Exception:
        return False


def _get_local_ips() -> set:
    """Return the set of IPs assigned to this host (for self-detection)."""
    global _LOCAL_IPS
    if _LOCAL_IPS is not None:
        return _LOCAL_IPS
    ips: set = set()
    try:
        r = subprocess.run(
            ["ip", "-o", "-4", "addr", "show"],
            capture_output=True, text=True, timeout=2
        )
        for line in r.stdout.splitlines():
            m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", line)
            if m:
                ips.add(m.group(1))
    except Exception:
        pass
    _LOCAL_IPS = ips
    return ips


def resolve_host(host: str) -> str:
    """Resolve a hostname to an IPv4 address (empty string on failure).

    Pure-IP inputs are returned unchanged. Used for self-detection when
    router sections use hostnames instead of literal addresses.
    """
    if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", host or ""):
        return host
    try:
        import socket
        return socket.gethostbyname(host)
    except Exception:
        return ""


def _get_local_hostname() -> str:
    """Return system hostname (lowercased, no domain).

    Used as a DNS-free self-detection method when the configured local
    router hostname does not resolve through DNS.
    """
    global _LOCAL_HOSTNAME
    if _LOCAL_HOSTNAME is not None:
        return _LOCAL_HOSTNAME
    name = ""
    try:
        with open("/proc/sys/kernel/hostname") as f:
            name = f.read().strip()
    except Exception:
        try:
            import socket
            name = socket.gethostname()
        except Exception:
            name = ""
    _LOCAL_HOSTNAME = name.lower()
    return _LOCAL_HOSTNAME


def is_local_router(host: str) -> bool:
    """True if host is the local router (run locally, skip SSH).

    Detection order (any match → local):
      1. Loopback literals.
      2. Hostname match against /proc/sys/kernel/hostname — survives DNS
         failures, the common case on this router (see _get_local_hostname).
      3. IP match — host's resolved IP is one of our own addresses.
    """
    if not host:
        return False
    h = host.lower()
    if h in ("127.0.0.1", "localhost"):
        return True
    local_name = _get_local_hostname()
    if local_name and h in (local_name, f"{local_name}.lan"):
        return True
    ip = resolve_host(host)
    if ip and ip in _get_local_ips():
        return True
    return False


def run_on_router(host: str, cmd: str, timeout: int = 10) -> tuple[bool, str]:
    """Execute a shell command on the given router.

    Runs locally (no SSH) when the host resolves to this router; otherwise
    via SSH. Returns (success, stdout). success=False on connection fail,
    non-zero exit, or timeout.
    """
    try:
        if is_local_router(host):
            result = subprocess.run(
                ["sh", "-c", cmd],
                capture_output=True, text=True, timeout=timeout
            )
        else:
            result = subprocess.run(
                [SSH_CMD, *SSH_OPTS, "-i", SSH_KEY, f"root@{host}", cmd],
                capture_output=True, text=True, timeout=timeout
            )
        if result.returncode != 0:
            return False, ""
        return True, result.stdout
    except subprocess.TimeoutExpired:
        return False, ""
    except Exception:
        return False, ""


def freq_to_band(freq_mhz: int) -> str:
    """Convert a WiFi frequency in MHz to a human-readable band label."""
    if 2400 <= freq_mhz <= 2500:
        return "2.4 GHz"
    if 5000 <= freq_mhz <= 5900:
        return "5 GHz"
    if 5925 <= freq_mhz <= 7125:
        return "6 GHz"
    return "unknown"


def format_bps(bps) -> str:
    """Format a raw rate in bps (from ubus) to a human string."""
    try:
        n = int(bps)
    except (ValueError, TypeError):
        return "—"
    if n <= 0:
        return "—"
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.1f} Gbps"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f} Mbps"
    if n >= 1_000:
        return f"{n / 1_000:.1f} kbps"
    return f"{n} bps"


def raw_bps(client_info: dict, direction: str) -> int:
    try:
        return int(((client_info or {}).get("rate", {}) or {}).get(direction, 0) or 0)
    except (ValueError, TypeError):
        return 0


def is_active_client(client_info: dict) -> bool:
    return bool((client_info or {}).get("assoc")) and bool((client_info or {}).get("authorized"))


def load_device_names() -> tuple:
    """
    Build authoritative MAC -> {name, ip} and IP -> {name, mac} maps.
    Priority (highest wins): static DHCP config > dynamic DHCP leases.
    Returns: (mac_map, ip_map)
    """
    mac_map: dict = {}
    ip_map:  dict = {}

    def add(mac: str, name: str, ip: str):
        if mac:
            mac_map[mac.lower()] = {"name": name, "ip": ip}
        if ip and name:
            ip_map[ip] = {"name": name, "mac": mac.lower() if mac else ""}

    # Dynamic DHCP leases cover unknown/new devices not yet in static config.
    try:
        with open("/tmp/dhcp.leases") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 4:
                    add(parts[1], parts[3] if parts[3] != "*" else "", parts[2])
    except Exception:
        pass

    # Authoritative: static DHCP config — overrides dynamic leases
    try:
        result = subprocess.run(
            ["uci", "show", "dhcp"],
            capture_output=True, text=True, timeout=5
        )
        cur: dict = {}
        for line in result.stdout.splitlines():
            if "=host" in line:
                if cur.get("mac") and cur.get("name"):
                    add(cur["mac"], cur["name"], cur.get("ip", ""))
                cur = {}
            m_mac  = re.search(r"\.mac='([^']+)'",  line, re.I)
            m_name = re.search(r"\.name='([^']+)'", line)
            m_ip   = re.search(r"\.ip='([^']+)'",   line)
            if m_mac:  cur["mac"]  = m_mac.group(1)
            if m_name: cur["name"] = m_name.group(1)
            if m_ip:   cur["ip"]   = m_ip.group(1)
        if cur.get("mac") and cur.get("name"):
            add(cur["mac"], cur["name"], cur.get("ip", ""))
    except Exception:
        pass

    return mac_map, ip_map


def format_connected_time(seconds_str) -> str:
    """Format seconds into '1d 5h 6m 35s' style string."""
    try:
        secs = int(seconds_str)
    except (ValueError, TypeError):
        return "unknown"
    d, rem = divmod(secs, 86400)
    h, rem = divmod(rem, 3600)
    m, s   = divmod(rem, 60)
    parts = []
    if d: parts.append(f"{d}d")
    if h: parts.append(f"{h}h")
    if m: parts.append(f"{m}m")
    parts.append(f"{s}s")
    return " ".join(parts)


# ─────────────────────────────────────────────────────────────────
# MAC Session Cache  — persists link-MAC → real-MAC mappings across
# collection cycles.  Entries expire after MAC_CACHE_TTL seconds.
# This lets us recognise MLD link MACs across reconnects within the
# same day without re-doing the bridge walk every 30 s.
# ─────────────────────────────────────────────────────────────────
MAC_CACHE_FILE = "/etc/wifi-clients/mac-cache.json"
MAC_CACHE_TTL  = 86400  # 24 h


def load_mac_cache() -> dict:
    """Return {link_mac: {real_mac, ts}} pruned of expired entries."""
    try:
        with open(MAC_CACHE_FILE) as f:
            raw = json.load(f)
        now = time.time()
        return {k: v for k, v in raw.items()
                if now - v.get("ts", 0) < MAC_CACHE_TTL}
    except Exception:
        return {}


def save_mac_cache(cache: dict) -> None:
    try:
        import os
        os.makedirs(os.path.dirname(MAC_CACHE_FILE), exist_ok=True)
        with open(MAC_CACHE_FILE, "w") as f:
            json.dump(cache, f)
    except Exception:
        pass


def get_bridge_data(router_host: str, iface_list: list) -> tuple:
    """
    Query the router's bridge MAC table and wifi-iface → bridge-port mapping.

    Returns:
        mac_to_port : {mac: port_num}   — every non-local MAC seen on br-lan
        port_to_macs: {port_num: [mac]} — reverse map
        iface_ports : {iface: port_num} — which bridge port each WiFi iface uses

    iface_list is passed in because interfaces are discovered dynamically
    per router via ubus.
    """
    mac_to_port:  dict = {}
    port_to_macs: dict = {}
    iface_ports:  dict = {}

    # 1. Bridge MAC table — try `bridge fdb` (modern) first, fall back to brctl
    ok, out = run_on_router(
        router_host,
        "bridge fdb show br br-lan 2>/dev/null || brctl showmacs br-lan 2>/dev/null",
        timeout=8
    )
    if ok:
        for line in out.splitlines():
            # bridge fdb format:  <mac> dev <iface> [vlan <n>] [master br-lan]
            m_fdb = re.match(
                r"\s*([0-9a-f:]{17})\s+dev\s+(\S+)", line, re.I
            )
            if m_fdb:
                mac   = m_fdb.group(1).lower()
                iface = m_fdb.group(2)
                # Use iface name hash as synthetic port id — good enough for
                # co-location grouping (clients on same iface = same "port").
                port = hash(iface) & 0xFFFF
                mac_to_port[mac] = port
                port_to_macs.setdefault(port, []).append(mac)
                iface_ports[iface] = port
                continue
            # brctl format: PORT  MAC  is_local  ageing_timer
            m_bc = re.match(
                r"\s*(\d+)\s+([0-9a-f:]{17})\s+(yes|no)", line, re.I
            )
            if m_bc and m_bc.group(3).lower() == "no":
                port = int(m_bc.group(1))
                mac  = m_bc.group(2).lower()
                mac_to_port[mac] = port
                port_to_macs.setdefault(port, []).append(mac)

    # 2. Interface → bridge-port via sysfs (authoritative for iface→port mapping)
    if iface_list:
        port_cmd = ";".join(
            f"p=$(cat /sys/class/net/{i}/brport/port_no 2>/dev/null); "
            f"[ -n \"$p\" ] && echo 'BRPORT:{i}:'$p"
            for i in iface_list
        )
        ok2, out2 = run_on_router(router_host, port_cmd, timeout=8)
        if ok2:
            for line in out2.splitlines():
                if line.startswith("BRPORT:"):
                    _, iface, port_s = line.split(":", 2)
                    try:
                        iface_ports[iface.strip()] = int(port_s.strip(), 0)
                    except ValueError:
                        pass

    return mac_to_port, port_to_macs, iface_ports


def build_arp_map(router_host: str) -> dict:
    """Return {real_mac: ip_addr} from the router's ARP/neighbour table."""
    arp_map = {}
    ok, out = run_on_router(router_host, "ip neigh show 2>/dev/null")
    if ok:
        for line in out.splitlines():
            m = re.search(
                r"(\d+\.\d+\.\d+\.\d+).*lladdr\s+([0-9a-f:]{17})",
                line, re.I
            )
            if m:
                arp_map[m.group(2).lower()] = m.group(1)
    return arp_map


def resolve_identity(
    link_mac:     str,
    bridge_port:  int | None,
    port_to_macs: dict,
    mac_to_port:  dict,          # used to filter ARP to locally-connected MACs only
    arp_map:      dict,
    mac_map:      dict,
    mac_cache:    dict,
    already_used: set,
    is_wds: bool = False,
) -> tuple:
    """
    Resolve a WiFi link MAC to a real device identity.
    Returns (real_mac, name, ip, method) where method is a debug string.

    Resolution order (most → least reliable):
      1. Direct match  — link_mac is the real MAC (non-randomised devices)
      2. Session cache — previously resolved and cached link→real mapping
      3. Bridge co-location — find a known device MAC on the same bridge port
         (most reliable for MLD/randomised: real MAC always traverses bridge)
      4. ARP table — IP cross-reference as last resort
    """
    lm = link_mac.lower()

    # 1. Direct
    if lm in mac_map:
        e = mac_map[lm]
        return lm, e["name"], e["ip"], "direct"

    # 2. Session cache
    cached = mac_cache.get(lm)
    if cached:
        rm = cached["real_mac"]
        if rm in mac_map and rm not in already_used:
            e = mac_map[rm]
            # Refresh TTL
            mac_cache[lm] = {"real_mac": rm, "ts": time.time()}
            return rm, e["name"], e["ip"], "cache"

    # 3. Bridge port co-location
    if bridge_port is not None:
        for co_mac in port_to_macs.get(bridge_port, []):
            if co_mac == lm:
                continue
            if co_mac in mac_map and co_mac not in already_used:
                e = mac_map[co_mac]
                if not e.get("name"):
                    continue
                # Persist to session cache
                mac_cache[lm] = {"real_mac": co_mac, "ts": time.time()}
                return co_mac, e["name"], e["ip"], "bridge"

    if is_wds:
        return lm, "", "", "unknown"

    # 4. ARP secondary source — only MACs directly connected to this router's bridge
    #    (mac_to_port keys = MACs seen in brctl showmacs = locally connected)
    #    Excludes subnet-wide ARP entries from other routers/devices
    for real_mac, ip_addr in arp_map.items():
        if real_mac == lm or real_mac in already_used:
            continue
        if real_mac not in mac_to_port:          # not directly on this router's bridge
            continue
        e = mac_map.get(real_mac)
        if e and e.get("name"):
            mac_cache[lm] = {"real_mac": real_mac, "ts": time.time()}
            return real_mac, e["name"], ip_addr, "arp"

    return lm, "", "", "unknown"


def discover_hostapd_ifaces(router_host: str) -> list:
    """Return list of hostapd interfaces on this router.

    Example outputs on MT7996E:
      ['ap-mld0', 'ap-mld1', 'ap-mld2', 'phy0.0-ap1', 'phy0.0-ap2', ...]

    Filters out:
      - 'global' (ubus object, not a real interface)
      - '<iface>_linkN' suffixes (per-link composite, duplicate of base MLD iface)
    """
    ok, out = run_on_router(router_host, "ubus list 'hostapd.*' 2>/dev/null", timeout=5)
    if not ok:
        return []
    ifaces = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("hostapd."):
            continue
        name = line[len("hostapd."):]
        if name == "global" or "_link" in name:
            continue
        if not _valid_iface(name):
            continue
        ifaces.append(name)
    return ifaces


def fetch_iface_status(router_host: str, ifaces: list) -> dict:
    """Return {iface: {ssid, band, freq}} via ubus get_status per interface."""
    info: dict = {}
    if not ifaces:
        return info
    # Batch: one SSH/local call yields all statuses
    cmd = "; ".join(
        f"echo '===ST:{i}==='; ubus call hostapd.{i} get_status 2>/dev/null || echo '{{}}'"
        for i in ifaces
    )
    ok, out = run_on_router(router_host, cmd, timeout=10)
    if not ok:
        return info
    cur_iface = None
    buf: list = []
    for line in out.splitlines():
        m = re.match(r"===ST:(\S+)===", line)
        if m:
            if cur_iface and buf:
                try:
                    status = json.loads("\n".join(buf))
                    freq = int(status.get("freq", 0) or 0)
                    info[cur_iface] = {
                        "ssid": status.get("ssid", ""),
                        "band": freq_to_band(freq),
                        "freq": freq,
                    }
                except Exception:
                    pass
            cur_iface = m.group(1)
            buf = []
        else:
            buf.append(line)
    # last chunk
    if cur_iface and buf:
        try:
            status = json.loads("\n".join(buf))
            freq = int(status.get("freq", 0) or 0)
            info[cur_iface] = {
                "ssid": status.get("ssid", ""),
                "band": freq_to_band(freq),
                "freq": freq,
            }
        except Exception:
            pass
    return info


def fetch_iface_clients(router_host: str, ifaces: list) -> dict:
    """Return {iface: {mac: client_info}} via ubus get_clients per interface."""
    result: dict = {}
    if not ifaces:
        return result
    cmd = "; ".join(
        f"echo '===CL:{i}==='; ubus call hostapd.{i} get_clients 2>/dev/null || echo '{{}}'"
        for i in ifaces
    )
    ok, out = run_on_router(router_host, cmd, timeout=15)
    if not ok:
        return result
    cur_iface = None
    buf: list = []
    for line in out.splitlines():
        m = re.match(r"===CL:(\S+)===", line)
        if m:
            if cur_iface and buf:
                try:
                    data = json.loads("\n".join(buf))
                    clients = data.get("clients", {}) or {}
                    result[cur_iface] = {mac.lower(): info for mac, info in clients.items()}
                except Exception:
                    pass
            cur_iface = m.group(1)
            buf = []
        else:
            buf.append(line)
    if cur_iface and buf:
        try:
            data = json.loads("\n".join(buf))
            clients = data.get("clients", {}) or {}
            result[cur_iface] = {mac.lower(): info for mac, info in clients.items()}
        except Exception:
            pass
    return result


def _parse_mcs_family(bitrate_line: str) -> str | None:
    """Extract MCS family prefix from an iw `rx bitrate` / `tx bitrate` line.

    iw emits one of these tokens right after the MBit/s + MHz fields:
      EHT-MCS  → 802.11be  (WiFi 7)
      HE-MCS   → 802.11ax  (WiFi 6 / 6E)
      VHT-MCS  → 802.11ac  (WiFi 5)
      MCS      → 802.11n   (WiFi 4)
      (none)   → 802.11a/b/g older generations

    Returns 'EHT' | 'HE' | 'VHT' | 'HT' | None.
    """
    if "EHT-MCS" in bitrate_line:
        return "EHT"
    if "HE-MCS" in bitrate_line:
        return "HE"
    if "VHT-MCS" in bitrate_line:
        return "VHT"
    # Bare 'MCS N' appears only for 11n; avoid matching EHT/HE/VHT-MCS here.
    if re.search(r"\bMCS\s+\d", bitrate_line):
        return "HT"
    return None


def fetch_iw_station_details(router_host: str, ifaces: list) -> dict:
    """Parse `iw dev <iface> station dump` for per-MAC PHY details.

    ubus get_clients doesn't expose connected_time OR the negotiated MCS
    family (EHT vs HE vs VHT); iw does. Returns
    {mac: {connected_time, signal_avg, mcs_family}} where mcs_family is the
    HIGHEST family seen on any direction ('EHT' > 'HE' > 'VHT' > 'HT').
    """
    result: dict = {}
    if not ifaces:
        return result
    cmd = "; ".join(
        f"echo '===IW:{i}==='; iw dev {i} station dump 2>/dev/null"
        for i in ifaces
    )
    ok, out = run_on_router(router_host, cmd, timeout=15)
    if not ok:
        return result

    rank = {"EHT": 4, "HE": 3, "VHT": 2, "HT": 1}

    cur_mac = None
    for line in out.splitlines():
        m_sta = re.match(r"Station\s+([0-9a-f:]{17})", line, re.I)
        if m_sta:
            cur_mac = m_sta.group(1).lower()
            result.setdefault(cur_mac, {})
            continue
        if cur_mac is None:
            continue
        m_ct = re.match(r"\s+connected time:\s+(\d+)\s+seconds", line)
        if m_ct:
            result[cur_mac]["connected_time"] = int(m_ct.group(1))
            continue
        m_sg = re.match(r"\s+signal avg:\s+(-?\d+)", line)
        if m_sg:
            result[cur_mac]["signal_avg"] = int(m_sg.group(1))
            continue
        # Both rx and tx bitrate lines can carry MCS tags — take max-rank.
        if "bitrate:" in line:
            fam = _parse_mcs_family(line)
            if fam:
                prev = result[cur_mac].get("mcs_family")
                if prev is None or rank[fam] > rank[prev]:
                    result[cur_mac]["mcs_family"] = fam
    return result


def detect_wifi_gen(ubus_client: dict, is_mld: bool, band: str, mcs_family: str | None = None) -> str:
    """Classify WiFi generation.

    Priority order:
      1. Negotiated MCS family from iw (authoritative — it's the actual PHY)
      2. ubus capability flags (ht/vht/he — what the client ADVERTISES)
      3. MLD multi-link (implies WiFi 7 even if we couldn't read MCS)

    On 6 GHz, HE means 6E (can only happen there). EHT on 6 GHz = WiFi 7 (6E+).
    """
    # MCS family from iw is the most reliable source.
    if mcs_family == "EHT":
        return "WiFi 7 (MLD)" if is_mld else "WiFi 7"
    if mcs_family == "HE":
        return "WiFi 6E" if band == "6 GHz" else "WiFi 6"
    if mcs_family == "VHT":
        return "WiFi 5"
    if mcs_family == "HT":
        return "WiFi 4"

    # Use ubus advertised caps when iw data is unavailable.
    if is_mld:
        return "WiFi 7 (MLD)"
    if bool(ubus_client.get("he")):
        return "WiFi 6E" if band == "6 GHz" else "WiFi 6"
    if bool(ubus_client.get("vht")):
        return "WiFi 5"
    if bool(ubus_client.get("ht")):
        return "WiFi 4"
    return "WiFi older"


def get_router_clients(router: dict) -> dict:
    """Collect WiFi clients from one router via ubus + iw.

    Returns dict with keys: online, clients, mac_to_port, port_to_macs,
    iface_ports, arp_map.

    Flow:
      1. Reachability check (ping, skip on local router)
      2. Discover hostapd interfaces
      3. Batch-fetch per-iface status (SSID/band) + clients + iw details
      4. MLD detection: same MAC on 2+ ap-mld* ifaces
      5. Build canonical client list (MLD entries de-duped, 6G link kept)
      6. Bridge + ARP for identity resolution
    """
    host = router["host"]

    # Fast reachability — skip on local router (ping to self always succeeds anyway
    # but we want to avoid the syscall).
    if not is_local_router(host) and not ping_check(host):
        return {"online": False, "clients": [], "arp_map": {},
                "mac_to_port": {}, "port_to_macs": {}, "iface_ports": {}}

    ifaces = discover_hostapd_ifaces(host)
    if not ifaces:
        # Router reachable but no hostapd interfaces configured
        return {"online": True, "clients": [], "arp_map": build_arp_map(host),
                "mac_to_port": {}, "port_to_macs": {}, "iface_ports": {}}

    iface_info   = fetch_iface_status(host, ifaces)     # {iface: {ssid, band, freq}}
    iface_cli    = fetch_iface_clients(host, ifaces)    # {iface: {mac: client_info}}
    iw_details   = fetch_iw_station_details(host, ifaces)  # {mac: {connected_time, signal_avg}}

    # Build MAC → list-of-ap-mld-ifaces map to detect MLD clients.
    # A MAC present on 2+ ap-mld* interfaces is a genuine MLD client.
    mac_to_mld_ifaces: dict = {}
    for iface, macs in iface_cli.items():
        if not iface.startswith("ap-mld"):
            continue
        for mac, cinfo in macs.items():
            if not is_active_client(cinfo):
                continue
            mac_to_mld_ifaces.setdefault(mac, []).append(iface)

    mld_macs = {m for m, ifs in mac_to_mld_ifaces.items() if len(ifs) >= 2}
    eht_ap_mld_macs = {
        m for m in mac_to_mld_ifaces
        if (iw_details.get(m, {}) or {}).get("mcs_family") == "EHT"
    }
    mld_candidate_macs = mld_macs | eht_ap_mld_macs

    # Prefer the 6 GHz (ap-mld2) entry for MLD clients — shows highest-band
    # signal/rate as primary in UI. If unavailable, use the highest-band iface.
    def pick_primary_iface(mac: str) -> str | None:
        if mac in mld_candidate_macs:
            # Prefer 6G > 5G > 2.4G for MLD clients
            order_pref = ["6 GHz", "5 GHz", "2.4 GHz"]
            by_band = {}
            for i in mac_to_mld_ifaces.get(mac, []):
                b = iface_info.get(i, {}).get("band", "unknown")
                by_band[b] = i
            for b in order_pref:
                if b in by_band:
                    return by_band[b]
            return mac_to_mld_ifaces[mac][0]
        # Non-MLD — return whichever iface holds this MAC (should be unique)
        for i, macs in iface_cli.items():
            if mac in macs and is_active_client(macs.get(mac)):
                return i
        return None

    # Assemble client list (unique per MAC). For MLD clients, capture both
    # primary and 6G-link details for the CGI renderer's mld_* fields.
    seen: set = set()
    clients = []

    # Sorted iteration: MLD first so they claim their entries before non-MLD duplicates
    all_macs = []
    for iface, macs in iface_cli.items():
        for mac in macs:
            all_macs.append(mac)
    # dedup + mld-first ordering
    mld_first = sorted(set(all_macs), key=lambda m: (m not in mld_candidate_macs, m))

    for mac in mld_first:
        if mac in seen:
            continue
        seen.add(mac)

        primary_iface = pick_primary_iface(mac)
        if not primary_iface or primary_iface not in iface_cli:
            continue
        cinfo = iface_cli[primary_iface].get(mac, {})
        info  = iface_info.get(primary_iface, {"ssid": "", "band": "unknown", "freq": 0})
        band  = info["band"]
        is_mld = mac in mld_candidate_macs
        mld_ifaces = mac_to_mld_ifaces.get(mac, []) if is_mld else []
        mld_links = []
        for i in mld_ifaces:
            link_band = iface_info.get(i, {}).get("band", "unknown")
            if link_band != "unknown" and link_band not in mld_links:
                mld_links.append(link_band)
        mld_links.sort(key=lambda b: {"2.4 GHz": 0, "5 GHz": 1, "6 GHz": 2}.get(b, 99))

        # Rates from ubus come as bps integers. Signal is dBm.
        rx_bps = raw_bps(cinfo, "rx")
        tx_bps = raw_bps(cinfo, "tx")
        signal = cinfo.get("signal")

        # 6G link details for MLD (ap-mld2 if present)
        mld_6g_info = None
        if is_mld:
            for i in mld_ifaces:
                if iface_info.get(i, {}).get("band") == "6 GHz":
                    mld_6g_info = iface_cli.get(i, {}).get(mac)
                    break

        mld_rx_6g = mld_tx_6g = None
        mld_sig_6g = None
        if mld_6g_info:
            mld_rx_6g = format_bps(raw_bps(mld_6g_info, "rx"))
            mld_tx_6g = format_bps(raw_bps(mld_6g_info, "tx"))
            mld_sig_6g = mld_6g_info.get("signal")

        if is_mld:
            for i in mld_ifaces:
                link_info = iface_cli.get(i, {}).get(mac, {}) or {}
                rx_bps = max(rx_bps, raw_bps(link_info, "rx"))
                tx_bps = max(tx_bps, raw_bps(link_info, "tx"))

        iw_info    = iw_details.get(mac, {}) or {}
        if is_mld and signal is None and iw_info.get("signal_avg") is not None:
            signal = iw_info.get("signal_avg")
        ct_secs    = int(iw_info.get("connected_time", 0) or 0)
        mcs_family = iw_info.get("mcs_family")

        client = {
            "mac":             mac,
            "iface":           primary_iface,
            "band":            band,
            "ssid":            info.get("ssid", ""),
            "router":          router["name"],
            "router_label":    router["label"],
            "signal":          str(signal) if signal is not None else "—",
            "rx_rate":         format_bps(rx_bps),
            "tx_rate":         format_bps(tx_bps),
            "connected_time":  format_connected_time(ct_secs),
            "connected_secs":  ct_secs,
            "is_mld":          is_mld,
            "mld_links":       mld_links,
            "mld_link_count":  len(mld_ifaces),
            "mld_rx_rate_6g":  mld_rx_6g,
            "mld_tx_rate_6g":  mld_tx_6g,
            "mld_signal_6g":   str(mld_sig_6g) if mld_sig_6g is not None else None,
            "wifi_gen":        detect_wifi_gen(cinfo, is_mld, band, mcs_family),
            "wds":             bool(cinfo.get("wds")),
        }
        clients.append(client)

    arp_map = build_arp_map(host)
    mac_to_port, port_to_macs, iface_ports = get_bridge_data(host, ifaces)

    # hostapd may expose WDS repeater AP virtual-interface MACs as extra
    # associated clients on the mesh SSID. Real WDS station MACs appear in the
    # bridge FDB; AP-VIF pseudo-clients do not. Hide the latter to avoid showing
    # duplicate/misidentified extenders.
    clients = [
        client for client in clients
        if not (client.get("wds") and client.get("mac") not in mac_to_port)
    ]

    # Attach resolution helpers (stripped before final output by collect_all)
    for client in clients:
        # WDS clients use per-station bridge ports (e.g. phy0.1-ap3.sta2),
        # not the parent AP bridge port. Prefer the client's own FDB port when
        # present so identity resolution sees the downstream extender MACs.
        client["_bridge_port"] = mac_to_port.get(client["mac"], iface_ports.get(client["iface"]))
        client["_port_to_macs"] = port_to_macs
        client["_arp_map"]      = arp_map

    return {
        "online": True,
        "clients": clients,
        "mac_to_port": mac_to_port,
        "port_to_macs": port_to_macs,
        "iface_ports": iface_ports,
        "arp_map": arp_map,
    }


def collect_all() -> dict:
    """
    Collect WiFi clients from all configured routers and resolve device identities.

    Identity resolution is 3-layered to handle WiFi 6/7 MAC randomisation
    and MLD link-address rotation:
      1. Session cache  — O(1) lookup for recently seen link MACs
      2. Bridge co-location — finds real MAC sharing the same br-lan port
      3. ARP secondary source — IP-based last resort
    """
    general, routers = load_config()
    mac_map, _ip_map = load_device_names()
    mac_cache = load_mac_cache()   # link_mac → {real_mac, ts}
    result = {
        "timestamp": datetime.now().isoformat(),
        "network_title": general.get("network_title") or DEFAULT_GENERAL["network_title"],
        "routers": [],
        "clients": [],
    }

    # Track which real MACs have already been claimed this cycle
    # so two link MACs don't both resolve to the same device record.
    already_used: set = set()

    # Parallelize router queries — offline routers no longer block online ones.
    # Total wall time = max(per-router time) instead of sum. Critical when 1+ routers
    # are offline — was 5s×N offline serial, now ~1s for all offline in parallel.
    with ThreadPoolExecutor(max_workers=max(1, len(routers))) as pool:
        router_results = [
            (router, pool.submit(get_router_clients, router))
            for router in routers
        ]

    for router, future in router_results:  # preserve display order
        router_result = future.result()
        result["routers"].append({
            "name":   router["name"],
            "label":  router["label"],
            "host":   router["host"],
            "online": router_result["online"],
            "count":  len(router_result["clients"]),
        })
        if not router_result["online"]:
            continue

        port_to_macs = router_result.get("port_to_macs", {})
        arp_map      = router_result.get("arp_map", {})

        # Prioritise MLD clients first so their real MACs get claimed before
        # any lone secondary links can grab the same identity.
        clients_sorted = sorted(
            router_result["clients"],
            key=lambda c: (-int(c.get("is_mld", 0)), -c.get("connected_secs", 0))
        )

        for client in clients_sorted:
            bridge_port = client.pop("_bridge_port", None)
            client.pop("_port_to_macs", None)
            client.pop("_arp_map",      None)

            mac_to_port  = router_result.get("mac_to_port", {})

            real_mac, name, ip, _method = resolve_identity(
                link_mac     = client["mac"],
                bridge_port  = bridge_port,
                port_to_macs = port_to_macs,
                mac_to_port  = mac_to_port,
                arp_map      = arp_map,
                mac_map      = mac_map,
                mac_cache    = mac_cache,
                already_used = already_used,
                is_wds      = bool(client.get("wds")),
            )

            client["name"]     = name
            client["ip"]       = ip
            client["real_mac"] = real_mac

            if real_mac and name:
                already_used.add(real_mac)

            result["clients"].append(client)

    # Persist updated cache
    save_mac_cache(mac_cache)

    # Final dedup: if somehow two entries share real_mac keep higher-priority one
    seen: dict = {}
    deduped = []
    for c in result["clients"]:
        rk = c.get("real_mac") or c["mac"]
        if rk not in seen:
            seen[rk] = True
            deduped.append(c)
    result["clients"] = deduped

    return result


if __name__ == "__main__":
    data = collect_all()
    json.dump(data, sys.stdout, indent=2)
    print()
