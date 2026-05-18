#!/bin/sh
# Configuration Management Library for wrtbwmon
# Loads, validates, and provides access to configuration values

# Prevent multiple sourcing (readonly variables can't be redeclared)
if [ "${_WRTBWMON_CONFIG_LOADED:-}" = "1" ]; then
    return 0
fi
_WRTBWMON_CONFIG_LOADED=1

# Ensure timezone is set for correct date/localtime operations
# On OpenWrt, musl reads /etc/TZ but cron may not have TZ env var set
# This is critical for PHT (UTC+8) and other non-UTC timezones
if [ -z "${TZ:-}" ] && [ -f /etc/TZ ]; then
    export TZ="$(cat /etc/TZ)"
fi

# Default configuration file location
readonly DEFAULT_CONFIG_FILE="/etc/wrtbwmon.conf"

# Configuration variables with defaults
CONFIG_LOADED=0

# Database configuration
DB_FILE="${DB_FILE:-/etc/wrtbwmon/traffic.db}"
DB_KEEP_DAYS="${DB_KEEP_DAYS:-90}"

# nftables configuration
NFT_TABLE="${NFT_TABLE:-netdev wrtbwmon_acct}"
NFT_MAP_V4="${NFT_MAP_V4:-wrtbwmon_dispatch_v4}"
NFT_MAP_V6="${NFT_MAP_V6:-wrtbwmon_dispatch_v6}"
NFTABLES_MAXELEM="${NFTABLES_MAXELEM:-65536}"

# Cleanup configuration
CLEANUP_ENABLED="${CLEANUP_ENABLED:-1}"
CLEANUP_INACTIVE_DAYS="${CLEANUP_INACTIVE_DAYS:-90}"

# Domain tracking configuration
DOMAIN_TRACKING_ENABLED="${DOMAIN_TRACKING_ENABLED:-1}"
DOMAIN_CACHE_TTL="${DOMAIN_CACHE_TTL:-604800}"
DNS_BACKEND="${DNS_BACKEND:-auto}"
DOMAIN_RETENTION_DAYS="${DOMAIN_RETENTION_DAYS:-90}"
TRAFFIC_RETENTION_DAYS="${TRAFFIC_RETENTION_DAYS:-90}"
RULE_INACTIVE_DAYS="${RULE_INACTIVE_DAYS:-7}"
MAX_DOMAINS_PER_DEVICE="${MAX_DOMAINS_PER_DEVICE:-5000}"

# Logging configuration
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_FILE="${LOG_FILE:-}"

# Source logger if available
if [ -f "/usr/lib/wrtbwmon/logger.sh" ]; then
    . /usr/lib/wrtbwmon/logger.sh
elif [ -f "$(dirname "$0")/logger.sh" ]; then
    . "$(dirname "$0")/logger.sh"
else
    # Fallback logging
    log_error() { echo "ERROR: $*" >&2; }
    log_warn() { echo "WARN: $*" >&2; }
    log_info() { echo "INFO: $*"; }
    log_debug() { :; }
fi

# Allowed configuration keys (prevent arbitrary code injection)
readonly _CONFIG_ALLOWED_KEYS="DB_FILE DB_KEEP_DAYS NFT_TABLE NFT_MAP_V4 NFT_MAP_V6 NFTABLES_MAXELEM CLEANUP_ENABLED CLEANUP_INACTIVE_DAYS DOMAIN_TRACKING_ENABLED DOMAIN_CACHE_TTL DNS_BACKEND DOMAIN_RETENTION_DAYS TRAFFIC_RETENTION_DAYS RULE_INACTIVE_DAYS MAX_DOMAINS_PER_DEVICE LOG_LEVEL LOG_FILE"

# Check if key is in allowed list
_config_key_allowed() {
    local key="$1"
    for allowed in $_CONFIG_ALLOWED_KEYS; do
        [ "$key" = "$allowed" ] && return 0
    done
    return 1
}

# Parse configuration file
# Format: KEY=value or KEY="value"
_config_parse_file() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log_warn "Configuration file not found: $config_file"
        return 1
    fi

    log_debug "Parsing configuration file: $config_file"

    # Read line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        case "$line" in
            \#*|'') continue ;;
        esac

        # Extract key=value
        local key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        local value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Remove quotes from value
        value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')

        # Skip if key is empty
        [ -z "$key" ] && continue

        # Validate key name (alphanumeric + underscore only, must be in allowlist)
        if ! echo "$key" | grep -qE '^[A-Z_][A-Z0-9_]*$'; then
            log_warn "Invalid config key name: $key (skipping)"
            continue
        fi

        if ! _config_key_allowed "$key"; then
            log_warn "Unknown config key: $key (skipping)"
            continue
        fi

        # Export as environment variable
        export "$key=$value"
        log_debug "Config: $key=$value"
    done < "$config_file"

    return 0
}

# Validate configuration values
_config_validate() {
    local errors=0

    # Validate DB_KEEP_DAYS
    if ! echo "$DB_KEEP_DAYS" | grep -qE '^[0-9]+$'; then
        log_error "Invalid DB_KEEP_DAYS: $DB_KEEP_DAYS (must be positive integer)"
        errors=$((errors + 1))
    fi

    # Validate NFTABLES_MAXELEM
    if ! echo "$NFTABLES_MAXELEM" | grep -qE '^[0-9]+$'; then
        log_error "Invalid NFTABLES_MAXELEM: $NFTABLES_MAXELEM (must be positive integer)"
        errors=$((errors + 1))
    fi

    # Validate CLEANUP_ENABLED
    if [ "$CLEANUP_ENABLED" != "0" ] && [ "$CLEANUP_ENABLED" != "1" ]; then
        log_error "Invalid CLEANUP_ENABLED: $CLEANUP_ENABLED (must be 0 or 1)"
        errors=$((errors + 1))
    fi

    # Validate DOMAIN_TRACKING_ENABLED
    if [ "$DOMAIN_TRACKING_ENABLED" != "0" ] && [ "$DOMAIN_TRACKING_ENABLED" != "1" ]; then
        log_error "Invalid DOMAIN_TRACKING_ENABLED: $DOMAIN_TRACKING_ENABLED (must be 0 or 1)"
        errors=$((errors + 1))
    fi

    # Validate DOMAIN_CACHE_TTL
    if ! echo "$DOMAIN_CACHE_TTL" | grep -qE '^[0-9]+$'; then
        log_error "Invalid DOMAIN_CACHE_TTL: $DOMAIN_CACHE_TTL (must be positive integer)"
        errors=$((errors + 1))
    fi

    # Validate LOG_LEVEL
    case "$LOG_LEVEL" in
        debug|info|warn|error|fatal) ;;
        *)
            log_error "Invalid LOG_LEVEL: $LOG_LEVEL (must be: debug, info, warn, error, fatal)"
            errors=$((errors + 1))
            ;;
    esac

    # Validate DNS_BACKEND
    case "$DNS_BACKEND" in
        auto|dnsmasq|adguard) ;;
        *)
            log_error "Invalid DNS_BACKEND: $DNS_BACKEND (must be: auto, dnsmasq, adguard)"
            errors=$((errors + 1))
            ;;
    esac

    # Validate database directory exists or can be created
    local db_dir=$(dirname "$DB_FILE")
    if [ ! -d "$db_dir" ]; then
        if ! mkdir -p "$db_dir" 2>/dev/null; then
            log_error "Cannot create database directory: $db_dir"
            errors=$((errors + 1))
        fi
    fi

    # Validate nftables table format
    if ! echo "$NFT_TABLE" | grep -qE '^[a-z]+ [a-z0-9_]+$'; then
        log_error "Invalid NFT_TABLE format: $NFT_TABLE (expected: 'family table')"
        errors=$((errors + 1))
    fi

    return $errors
}

_config_bool() {
    case "$1" in
        1|true|yes|on|enabled) printf '1' ;;
        *) printf '0' ;;
    esac
}

_config_apply_uci() {
    command -v uci >/dev/null 2>&1 || return 0
    local value
    value=$(uci -q get wrtbwmon.general.db_file 2>/dev/null || true)
    [ -n "$value" ] && DB_FILE="$value"
    value=$(uci -q get wrtbwmon.general.db_keep_days 2>/dev/null || true)
    [ -n "$value" ] && DB_KEEP_DAYS="$value"
    value=$(uci -q get wrtbwmon.general.cleanup_enabled 2>/dev/null || true)
    [ -n "$value" ] && CLEANUP_ENABLED=$(_config_bool "$value")
    value=$(uci -q get wrtbwmon.general.cleanup_inactive_days 2>/dev/null || true)
    [ -n "$value" ] && CLEANUP_INACTIVE_DAYS="$value"
    value=$(uci -q get wrtbwmon.general.domain_tracking 2>/dev/null || true)
    [ -n "$value" ] && DOMAIN_TRACKING_ENABLED=$(_config_bool "$value")
    value=$(uci -q get wrtbwmon.general.domain_cache_ttl 2>/dev/null || true)
    [ -n "$value" ] && DOMAIN_CACHE_TTL="$value"
    value=$(uci -q get wrtbwmon.general.dns_backend 2>/dev/null || true)
    [ -n "$value" ] && DNS_BACKEND="$value"
    value=$(uci -q get wrtbwmon.general.log_level 2>/dev/null || true)
    [ -n "$value" ] && LOG_LEVEL="$value"
}

# Load configuration from file
# Usage: config_load [config_file]
config_load() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"

    log_info "Loading configuration from: $config_file"

    # Parse configuration file
    if _config_parse_file "$config_file"; then
        log_debug "Configuration file parsed successfully"
    else
        log_warn "Using default configuration values"
    fi

    _config_apply_uci

    # Validate configuration
    if _config_validate; then
        log_info "Configuration validated successfully"
        CONFIG_LOADED=1
        return 0
    else
        log_error "Configuration validation failed"
        return 1
    fi
}

# Get configuration value
# Usage: value=$(config_get "DB_FILE")
config_get() {
    local key="$1"

    # Validate key to prevent injection via eval
    if ! echo "$key" | grep -qE '^[A-Z_][A-Z0-9_]*$'; then
        log_error "Invalid config key: $key"
        return 1
    fi

    eval "printf '%s' \"\${$key}\""
}

# Set configuration value (runtime only, not persisted)
# Usage: config_set "LOG_LEVEL" "debug"
config_set() {
    local key="$1"
    local value="$2"

    # Validate key to prevent injection
    if ! echo "$key" | grep -qE '^[A-Z_][A-Z0-9_]*$'; then
        log_error "Invalid config key: $key"
        return 1
    fi

    export "$key=$value"
    log_debug "Config updated: $key=$value"
}

# Check if configuration is loaded
# Usage: config_is_loaded && echo "Config loaded"
config_is_loaded() {
    [ "$CONFIG_LOADED" = "1" ]
}

# Require configuration is loaded
# Usage: config_require
config_require() {
    if ! config_is_loaded; then
        log_error "Configuration not loaded. Call config_load first."
        return 1
    fi
}

# Print current configuration
# Usage: config_print
config_print() {
    echo "=== wrtbwmon Configuration ==="
    echo ""
    echo "Database:"
    echo "  DB_FILE=$DB_FILE"
    echo "  DB_KEEP_DAYS=$DB_KEEP_DAYS"
    echo ""
    echo "nftables:"
    echo "  NFT_TABLE=$NFT_TABLE"
    echo "  NFT_MAP_V4=$NFT_MAP_V4"
    echo "  NFT_MAP_V6=$NFT_MAP_V6"
    echo "  NFTABLES_MAXELEM=$NFTABLES_MAXELEM"
    echo ""
    echo "Cleanup:"
    echo "  CLEANUP_ENABLED=$CLEANUP_ENABLED"
    echo "  CLEANUP_INACTIVE_DAYS=$CLEANUP_INACTIVE_DAYS"
    echo ""
    echo "Domain Tracking:"
    echo "  DOMAIN_TRACKING_ENABLED=$DOMAIN_TRACKING_ENABLED"
    echo "  DOMAIN_CACHE_TTL=$DOMAIN_CACHE_TTL"
    echo "  DNS_BACKEND=$DNS_BACKEND"
    echo "  DOMAIN_RETENTION_DAYS=$DOMAIN_RETENTION_DAYS"
    echo "  TRAFFIC_RETENTION_DAYS=$TRAFFIC_RETENTION_DAYS"
    echo "  RULE_INACTIVE_DAYS=$RULE_INACTIVE_DAYS"
    echo "  MAX_DOMAINS_PER_DEVICE=$MAX_DOMAINS_PER_DEVICE"
    echo ""
    echo "Logging:"
    echo "  LOG_LEVEL=$LOG_LEVEL"
    echo "  LOG_FILE=$LOG_FILE"
    echo ""
}

# Export all configuration as environment variables
# Usage: config_export
config_export() {
    export DB_FILE
    export DB_KEEP_DAYS
    export NFT_TABLE
    export NFT_MAP_V4
    export NFT_MAP_V6
    export NFTABLES_MAXELEM
    export CLEANUP_ENABLED
    export CLEANUP_INACTIVE_DAYS
    export DOMAIN_TRACKING_ENABLED
    export DOMAIN_CACHE_TTL
    export DNS_BACKEND
    export DOMAIN_RETENTION_DAYS
    export TRAFFIC_RETENTION_DAYS
    export RULE_INACTIVE_DAYS
    export MAX_DOMAINS_PER_DEVICE
    export LOG_LEVEL
    export LOG_FILE

    log_debug "Configuration exported to environment"
}

# Create default configuration file
# Usage: config_create_default [output_file]
config_create_default() {
    local output_file="${1:-$DEFAULT_CONFIG_FILE}"

    log_info "Creating default configuration: $output_file"

    cat > "$output_file" << 'EOF'
# wrtbwmon Configuration File
# This file is sourced by all wrtbwmon scripts

# Database Configuration
DB_FILE="/etc/wrtbwmon/traffic.db"
DB_KEEP_DAYS=90

# nftables Configuration
NFT_TABLE="netdev wrtbwmon_acct"
NFT_MAP_V4="wrtbwmon_dispatch_v4"
NFT_MAP_V6="wrtbwmon_dispatch_v6"
NFTABLES_MAXELEM=65536

# Cleanup Configuration
CLEANUP_ENABLED=1
CLEANUP_INACTIVE_DAYS=90

# Domain Tracking Configuration
DOMAIN_TRACKING_ENABLED=1
DOMAIN_CACHE_TTL=604800
DNS_BACKEND="auto"
DOMAIN_RETENTION_DAYS=90
TRAFFIC_RETENTION_DAYS=90
RULE_INACTIVE_DAYS=7
MAX_DOMAINS_PER_DEVICE=5000

# Logging Configuration
# Valid levels: debug, info, warn, error, fatal
LOG_LEVEL="info"
LOG_FILE=""
EOF

    log_info "Default configuration created: $output_file"
}

# Test function
_config_test() {
    echo "=== Configuration Manager Test ==="

    # Enable logging
    LOG_TO_STDOUT=1
    log_set_level "debug"

    echo ""
    echo "Test 1: Create default configuration"
    local test_config="/tmp/wrtbwmon_test.conf"
    config_create_default "$test_config"

    echo ""
    echo "Test 2: Load configuration"
    config_load "$test_config"

    echo ""
    echo "Test 3: Get configuration values"
    echo "  DB_FILE=$(config_get DB_FILE)"
    echo "  LOG_LEVEL=$(config_get LOG_LEVEL)"

    echo ""
    echo "Test 4: Set configuration value"
    config_set "LOG_LEVEL" "debug"
    echo "  LOG_LEVEL=$(config_get LOG_LEVEL)"

    echo ""
    echo "Test 5: Print configuration"
    config_print

    echo ""
    echo "Test 6: Cleanup"
    rm -f "$test_config"
    echo "  Removed test configuration"

    echo ""
    echo "=== Test Complete ==="
}

# Run test if executed directly
if [ "${0##*/}" = "config.sh" ]; then
    case "${1:-}" in
        test)
            _config_test
            ;;
        print)
            config_load
            config_print
            ;;
        create)
            config_create_default "${2:-$DEFAULT_CONFIG_FILE}"
            ;;
        *)
            echo "Usage: $0 {test|print|create [file]}"
            echo ""
            echo "Or source this file in your script:"
            echo "  . /usr/lib/wrtbwmon/config.sh"
            echo "  config_load"
            echo ""
            echo "Available functions:"
            echo "  config_load             - Load configuration file"
            echo "  config_get              - Get configuration value"
            echo "  config_set              - Set configuration value"
            echo "  config_print            - Print current configuration"
            echo "  config_export           - Export to environment"
            echo "  config_create_default   - Create default config file"
            ;;
    esac
fi
