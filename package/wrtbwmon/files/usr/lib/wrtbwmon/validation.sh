#!/bin/sh
# Input Validation Library for wrtbwmon
# Provides secure input validation and sanitization functions
# Prevents SQL injection, command injection, and other input-based attacks

# Library paths
LIB_DIR="/usr/lib/wrtbwmon"
[ -d "/usr/sbin/../lib/wrtbwmon" ] && LIB_DIR="/usr/sbin/../lib/wrtbwmon"

# Optional: Source logger for validation error logging (if available)
if [ -f "$LIB_DIR/logger.sh" ]; then
    . "$LIB_DIR/logger.sh"
    # Initialize library logging (only if not already initialized)
    if [ -z "$_LOGGER_INITIALIZED" ]; then
        log_init "wrtbwmon-validation" "${LOG_LEVEL:-info}"
    fi
fi

# Validate IPv4 address
# Usage: validate_ipv4 "192.168.1.1"
# Returns: 0 on success, 1 on failure
validate_ipv4() {
    local ip="$1"

    # Reject unusable addresses (AdGuard-blocked, null routes)
    [ "$ip" = "0.0.0.0" ] && return 1

    # Reject leading zeros in octets (e.g., 08, 007) — causes octal interpretation
    echo "$ip" | grep -qE '(^|\.)(0[0-9]+)' && return 1

    # Check format: xxx.xxx.xxx.xxx and each octet is 0-255
    echo "$ip" | awk -F. 'NF==4 && $1>=0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>=0 && $4<=255' | grep -q . || return 1

    return 0
}

# Validate IPv6 address (simplified)
# Usage: validate_ipv6 "2001:db8::1"
# Returns: 0 on success, 1 on failure
validate_ipv6() {
    local ip="$1"

    # Basic IPv6 format check
    echo "$ip" | grep -qE '^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$' || return 1

    return 0
}

# Validate IP address (IPv4 or IPv6)
# Usage: validate_ip "192.168.1.1"
# Returns: 0 on success, 1 on failure
validate_ip() {
    local ip="$1"

    [ -z "$ip" ] && return 1

    # Try IPv4 first
    if echo "$ip" | grep -q '\.'; then
        validate_ipv4 "$ip"
        return $?
    fi

    # Try IPv6
    if echo "$ip" | grep -q ':'; then
        validate_ipv6 "$ip"
        return $?
    fi

    return 1
}

# Validate MAC address
# Usage: validate_mac "aa:bb:cc:dd:ee:ff"
# Returns: 0 on success, 1 on failure
validate_mac() {
    local mac="$1"

    [ -z "$mac" ] && return 1

    # Check format: xx:xx:xx:xx:xx:xx (case insensitive)
    echo "$mac" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1

    return 0
}

# Sanitize domain name
# Usage: domain=$(sanitize_domain "example.com")
# Returns: Sanitized domain name (max 253 chars)
sanitize_domain() {
    local domain="$1"

    [ -z "$domain" ] && return 1

    # Remove all characters except alphanumeric, dots, and dashes
    # Limit to 253 characters (DNS limit)
    echo "$domain" | tr -cd 'a-zA-Z0-9.-' | head -c 253
}

# Validate domain name
# Usage: validate_domain "example.com"
# Returns: 0 on success, 1 on failure
validate_domain() {
    local domain="$1"

    [ -z "$domain" ] && return 1

    # Check length (3-253 chars — minimum is a.bc)
    local len=${#domain}
    [ "$len" -lt 3 ] || [ "$len" -gt 253 ] && return 1

    # Must contain at least one dot (valid FQDN)
    echo "$domain" | grep -q '\.' || return 1

    # Check format: alphanumeric, dots, dashes only
    echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$' || return 1

    # Check no consecutive dots
    echo "$domain" | grep -q '\.\.' && return 1

    # Check doesn't start or end with dot or dash
    echo "$domain" | grep -qE '^[.-]|[.-]$' && return 1

    return 0
}

# SQL-safe string escaping
# Usage: safe_str=$(sql_escape "user's input")
# Returns: Escaped string safe for SQL
sql_escape() {
    local str="$1"

    # Escape single quotes by doubling them (SQL standard)
    echo "$str" | sed "s/'/''/g"
}

# Validate SQL table name (prevent injection)
# Usage: validate_table_name "devices" || return 1
# Returns: 0 on success, 1 on failure
validate_table_name() {
    local table="$1"

    [ -z "$table" ] && return 1

    # Only lowercase alphanumeric and underscore, must start with letter/underscore
    echo "$table" | grep -qE '^[a-z_][a-z0-9_]*$' || return 1

    return 0
}

# Validate interface name
# Usage: validate_interface "br-lan"
# Returns: 0 on success, 1 on failure
validate_interface() {
    local iface="$1"

    [ -z "$iface" ] && return 1

    # Check format: alphanumeric, dash, underscore, dot (max 15 chars)
    echo "$iface" | grep -qE '^[a-zA-Z0-9._-]{1,15}$' || return 1

    return 0
}

# Validate positive integer
# Usage: validate_positive_int "123"
# Returns: 0 on success, 1 on failure
validate_positive_int() {
    local num="$1"

    [ -z "$num" ] && return 1

    # Check if it's a positive integer
    echo "$num" | grep -qE '^[0-9]+$' || return 1

    return 0
}

# Validate timestamp (Unix epoch)
# Usage: validate_timestamp "1234567890"
# Returns: 0 on success, 1 on failure
validate_timestamp() {
    local ts="$1"

    [ -z "$ts" ] && return 1

    # Check if it's a positive integer
    validate_positive_int "$ts" || return 1

    # Check reasonable range (after 2000-01-01 and before 2100-01-01)
    [ "$ts" -ge 946684800 ] && [ "$ts" -le 4102444800 ] || return 1

    return 0
}

# Create secure temporary file
# Usage: tmpfile=$(create_temp_file "prefix")
# Returns: Path to temporary file
# Note: Caller must clean up with trap
create_temp_file() {
    local prefix="${1:-wrtbwmon}"

    mktemp "/tmp/${prefix}.XXXXXX"
}

# Setup cleanup trap for temporary files
# Usage: setup_cleanup_trap "$tmpfile1" "$tmpfile2"
# Side effect: Sets up EXIT/INT/TERM trap
setup_cleanup_trap() {
    local files="$*"

    # shellcheck disable=SC2064
    trap "rm -f '$files'" EXIT INT TERM
}
