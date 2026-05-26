#!/bin/sh
# DNS Backend: AdGuard Home
# Queries AdGuard API for DNS logs
#
# Default release expectation is a local, unauthenticated AdGuard Home
# querylog endpoint on http://127.0.0.1:3000, matching the standard setup
# used by this firmware. For non-default protected AdGuard deployments, set
# ADGUARD_AUTH to the username:password or API token, e.g.:
#   export ADGUARD_AUTH="admin:password"
#   export ADGUARD_AUTH="Bearer <api_token>"
# Without auth, the API will return empty results or 401 errors.

# Parse AdGuard API for DNS mappings
# Returns: Writes to MAPPINGS_FILE
dns_backend_adguard_parse() {
    local mappings_file="$1"
    local current_timestamp=$(date +%s)
    local adguard_api="${ADGUARD_API:-http://127.0.0.1:3000/control/querylog?search=&response_status=processed&older_than=&limit=500}"

    # Clear output file
    > "$mappings_file"

    local tmp_json
    tmp_json="$(mktemp /tmp/wrtbwmon-adguard.XXXXXX)" || return 1

    if [ -n "${ADGUARD_AUTH:-}" ]; then
        case "$ADGUARD_AUTH" in
            Bearer\ *) curl -s -H "Authorization: $ADGUARD_AUTH" "$adguard_api" > "$tmp_json" 2>/dev/null ;;
            *:*) curl -s -u "$ADGUARD_AUTH" "$adguard_api" > "$tmp_json" 2>/dev/null ;;
            *) curl -s -H "Authorization: Bearer $ADGUARD_AUTH" "$adguard_api" > "$tmp_json" 2>/dev/null ;;
        esac
    else
        curl -s "$adguard_api" > "$tmp_json" 2>/dev/null
    fi

    python3 - "$tmp_json" "$mappings_file" "$current_timestamp" <<'PY'
import ipaddress
import json
import sys

json_path, mappings_path, timestamp = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(json_path, "r", encoding="utf-8") as fh:
        payload = json.load(fh)
except Exception:
    sys.exit(0)

if isinstance(payload, dict):
    entries = payload.get("data") or payload.get("querylog") or payload.get("logs") or []
else:
    entries = payload

if not isinstance(entries, list):
    sys.exit(0)

with open(mappings_path, "a", encoding="utf-8") as out:
    for entry in entries:
        if not isinstance(entry, dict):
            continue

        question = entry.get("question") or {}
        domain = question.get("name") or entry.get("domain") or entry.get("name") or ""
        domain = str(domain).rstrip(".")
        if not domain:
            continue

        answers = entry.get("answers")
        if answers is None:
            answers = entry.get("answer")
        if isinstance(answers, dict):
            answers = [answers]
        if not isinstance(answers, list):
            continue

        for answer in answers:
            if not isinstance(answer, dict):
                continue

            record_type = str(answer.get("type") or "").upper()
            value = answer.get("value") or answer.get("address") or answer.get("data") or answer.get("ip") or ""

            try:
                ip = ipaddress.ip_address(str(value))
            except ValueError:
                continue

            if ip.version == 4 and (not record_type or record_type == "A"):
                out.write(f"{ip}|{domain}|{timestamp}\n")
PY
    rm -f "$tmp_json"
}

# Check if AdGuard backend is available
dns_backend_adguard_available() {
    local adguard_api="${ADGUARD_API:-http://127.0.0.1:3000/control/querylog}"
    if [ -n "${ADGUARD_AUTH:-}" ]; then
        case "$ADGUARD_AUTH" in
            Bearer\ *) curl -s -f -m 2 -H "Authorization: $ADGUARD_AUTH" "$adguard_api" >/dev/null 2>&1 ;;
            *:*) curl -s -f -m 2 -u "$ADGUARD_AUTH" "$adguard_api" >/dev/null 2>&1 ;;
            *) curl -s -f -m 2 -H "Authorization: Bearer $ADGUARD_AUTH" "$adguard_api" >/dev/null 2>&1 ;;
        esac
    else
        curl -s -f -m 2 "$adguard_api" >/dev/null 2>&1
    fi
}
