import json
import re
import subprocess


def table_args(table):
    return table.split()


def run_nft(args, timeout=15, input_text=None):
    return subprocess.run(
        ["nft"] + args,
        input=input_text,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def list_table_json(table, timeout=15):
    proc = run_nft(["-j", "list", "table"] + table_args(table), timeout=timeout)
    if proc.returncode != 0:
        return None, proc
    try:
        return json.loads(proc.stdout), proc
    except json.JSONDecodeError:
        return None, proc


def list_table_text(table, timeout=15):
    return run_nft(["list", "table"] + table_args(table), timeout=timeout)


def list_chain_text(table, chain, timeout=5, handles=False):
    args = []
    if handles:
        args.append("-a")
    args += ["list", "chain"] + table_args(table) + [chain]
    return run_nft(args, timeout=timeout)


def list_sets_text(table, timeout=10):
    return run_nft(["list", "sets"] + table_args(table), timeout=timeout)


def nft_objects(data, key):
    if not data:
        return []
    return [obj[key] for obj in data.get("nftables", []) if key in obj]


def counter_bytes(rule):
    for expr in rule.get("expr", []):
        counter = expr.get("counter") if isinstance(expr, dict) else None
        if counter:
            return int(counter.get("bytes", 0) or 0)
    return 0


def rule_comment(rule):
    return rule.get("comment") or ""


def chain_to_ipv4(chain_name):
    m = re.match(r"device_(\d+)_(\d+)_(\d+)_(\d+)$", chain_name or "")
    if not m:
        return None
    return f"{m.group(1)}.{m.group(2)}.{m.group(3)}.{m.group(4)}"


def domain_chain_to_mac(chain_name):
    m = re.match(r"device_domains_([0-9a-fA-F]{12})$", chain_name or "")
    if not m:
        return None
    mac_clean = m.group(1).lower()
    return ":".join(mac_clean[i:i + 2] for i in range(0, 12, 2))


def rule_set_ref(rule):
    for expr in rule.get("expr", []):
        match = expr.get("match") if isinstance(expr, dict) else None
        if not match:
            continue
        right = match.get("right")
        if isinstance(right, str) and right.startswith("@"):
            return right[1:]
    return None


def parse_map_keys_from_text(text, map_name):
    keys = {}
    in_map = False
    for line in text.splitlines():
        s = line.strip()
        if re.match(rf"map\s+{re.escape(map_name)}\b", s):
            in_map = True
            continue
        if in_map and s == "}":
            in_map = False
            continue
        if in_map:
            m = re.search(r"(\d+\.\d+\.\d+\.\d+)\s*:\s*jump\s+(\S+)", s)
            if m:
                keys[m.group(1)] = m.group(2).rstrip(",")
    return keys
