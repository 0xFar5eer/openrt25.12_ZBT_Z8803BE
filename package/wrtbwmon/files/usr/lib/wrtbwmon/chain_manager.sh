#!/bin/sh
# Chain Manager for wrtbwmon
# High-level abstraction layer for all nftables operations
# Provides consistent API for chains, sets, rules, maps, and counters

# Library paths
LIB_DIR="/usr/lib/wrtbwmon"
[ -d "/usr/sbin/../lib/wrtbwmon" ] && LIB_DIR="/usr/sbin/../lib/wrtbwmon"

# Source core libraries
. "$LIB_DIR/logger.sh" || { echo "ERROR: logger.sh not found" >&2; return 1; }
. "$LIB_DIR/error_handler.sh" || { echo "ERROR: error_handler.sh not found" >&2; return 1; }
. "$LIB_DIR/config.sh" || { echo "ERROR: config.sh not found" >&2; return 1; }

# Source validation library
if [ -f "$LIB_DIR/validation.sh" ]; then
    . "$LIB_DIR/validation.sh"
else
    log_error "validation.sh not found"
    return 1
fi

# Initialize library logging (only if not already initialized)
if [ -z "$_LOGGER_INITIALIZED" ]; then
    log_init "wrtbwmon-chain" "${LOG_LEVEL:-info}"
fi

#=============================================================================
# Core nftables Command Wrapper
#=============================================================================

# Execute nft command with error handling
# Usage: _nft_exec <command> [args...]
# Returns: 0 on success, 1 on failure
_nft_exec() {
    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) not found"
        return 1
    fi

    nft "$@" 2>/dev/null
}

# Get default table name from config
_nft_get_table() {
    local table
    table=$(config_get "NFT_TABLE")
    [ -z "$table" ] && table="inet fw4"
    echo "$table"
}

#=============================================================================
# Batch nftables Execution
#=============================================================================

# Execute multiple nft commands from a file via nft -f (single subprocess)
# Usage: nft_batch_execute <file>
# Returns: 0 on success, 1 on failure
nft_batch_execute() {
    local batch_file="$1"
    [ ! -s "$batch_file" ] && return 0
    nft -f "$batch_file" 2>/dev/null
}

# Cache nftables state to avoid repeated nft list calls
# Usage: nft_cache_state
# Sets: _NFT_CACHED_CHAINS, _NFT_CACHED_SETS, _NFT_CACHED_RULES, _NFT_CACHED_MAP
nft_cache_state() {
    local table
    table=$(_nft_get_table)
    _NFT_CACHED_TABLE="$table"
    _NFT_CACHED_CHAINS=$(_nft_exec list table "$table" 2>/dev/null | grep "chain " | awk '{print $2}' | sed 's/{//')
    _NFT_CACHED_SETS=$(_nft_exec list sets "$table" 2>/dev/null | grep "set " | awk '{print $2}' | sed 's/{//')
    _NFT_CACHED_MAP=$(_nft_exec list map "$table" wrtbwmon_domain_dispatch_v4 2>/dev/null)
    _NFT_CACHED_DISPATCH=$(_nft_exec list chain "$table" forward 2>/dev/null | grep "wrtbwmon-dispatch")
}

# Check if chain exists using cached state
# Usage: nft_chain_cached <chain_name>
nft_chain_cached() {
    echo "$_NFT_CACHED_CHAINS" | grep -qx "$1"
}

# Check if set exists using cached state
# Usage: nft_set_cached <set_name>
nft_set_cached() {
    echo "$_NFT_CACHED_SETS" | grep -qx "$1"
}

#=============================================================================
# Chain Management API
#=============================================================================

# Check if chain exists
# Usage: nft_chain_exists <chain_name> [table]
# Returns: 0 if exists, 1 if not
nft_chain_exists() {
    local chain_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    _nft_exec list chain "$table" "$chain_name" >/dev/null 2>&1
}

# Create chain
# Usage: nft_chain_create <chain_name> [table] [hook_spec]
# hook_spec: "type filter hook forward priority 0;" for base chains
# Returns: 0 on success, 1 on failure
nft_chain_create() {
    local chain_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"
    local hook_spec="$3"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    # Check if already exists
    if nft_chain_exists "$chain_name" "$table"; then
        log_debug "Chain $chain_name already exists"
        return 0
    fi

    # Create chain
    if [ -n "$hook_spec" ]; then
        _nft_exec add chain "$table" "$chain_name" "{ $hook_spec }"
    else
        _nft_exec add chain "$table" "$chain_name"
    fi
}

# Delete chain
# Usage: nft_chain_delete <chain_name> [table]
# Returns: 0 on success, 1 on failure
nft_chain_delete() {
    local chain_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    _nft_exec delete chain "$table" "$chain_name" 2>/dev/null || true
    return 0
}

# Flush chain (remove all rules)
# Usage: nft_chain_flush <chain_name> [table]
# Returns: 0 on success, 1 on failure
nft_chain_flush() {
    local chain_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    _nft_exec flush chain "${table:-$(_nft_get_table)}" "$chain_name"
}

# List all chains in table
# Usage: nft_chain_list [table] [pattern]
# Returns: Chain names (one per line)
nft_chain_list() {
    local table="${1:-$(_nft_get_table)}"
    local pattern="$2"

    if [ -n "$pattern" ]; then
        _nft_exec list table "$table" 2>/dev/null | grep "chain $pattern" | awk '{print $2}'
    else
        _nft_exec list table "$table" 2>/dev/null | grep "^[[:space:]]*chain " | awk '{print $2}'
    fi
}

# Get chain content
# Usage: nft_chain_get <chain_name> [table]
# Returns: Chain rules and counters
nft_chain_get() {
    local chain_name="$1"
    local table="${2:-$(_nft_get_table)}"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    _nft_exec list chain "${table:-$(_nft_get_table)}" "$chain_name" 2>/dev/null
}

#=============================================================================
# Set Management API
#=============================================================================

# Check if set exists
# Usage: nft_set_exists <set_name> [table]
# Returns: 0 if exists, 1 if not
nft_set_exists() {
    local set_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$set_name" ]; then
        log_error "Set name is required"
        return 1
    fi

    _nft_exec list set "$table" "$set_name" >/dev/null 2>&1
}

# Create set
# Usage: nft_set_create <set_name> <type> [table] [flags] [comment]
# type: ipv4_addr, ipv6_addr, ether_addr, etc.
# flags: interval, timeout, etc. (space-separated)
# Returns: 0 on success, 1 on failure
nft_set_create() {
    local set_name="$1"
    local type="$2"
    local table="${3:-$(_nft_get_table)}"
    local flags="$4"
    local comment="$5"

    if [ -z "$set_name" ] || [ -z "$type" ]; then
        log_error "Set name and type are required"
        return 1
    fi

    # Check if already exists
    if nft_set_exists "$set_name" "$table"; then
        log_debug "Set $set_name already exists"
        return 0
    fi

    # Build set definition
    local set_def="type $type;"
    [ -n "$flags" ] && set_def="$set_def flags $flags;"
    [ -n "$comment" ] && set_def="$set_def comment \"$comment\";"

    _nft_exec add set "${table:-$(_nft_get_table)}" "$set_name" "{ $set_def }"
}

# Delete set
# Usage: nft_set_delete <set_name> [table]
# Returns: 0 on success, 1 on failure
nft_set_delete() {
    local set_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$set_name" ]; then
        log_error "Set name is required"
        return 1
    fi

    _nft_exec delete set "${table:-$(_nft_get_table)}" "$set_name" 2>/dev/null || true
    return 0
}

# Add element to set
# Usage: nft_set_add_element <set_name> <element> [table]
# Returns: 0 on success, 1 on failure
nft_set_add_element() {
    local set_name="$1"
    local element="$2"
    local table="${3:-$(_nft_get_table)}"

    if [ -z "$set_name" ] || [ -z "$element" ]; then
        log_error "Set name and element are required"
        return 1
    fi

    _nft_exec add element "${table:-$(_nft_get_table)}" "$set_name" "{ $element }"
}

# Delete element from set
# Usage: nft_set_delete_element <set_name> <element> [table]
# Returns: 0 on success, 1 on failure
nft_set_delete_element() {
    local set_name="$1"
    local element="$2"
    local table="$3"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$set_name" ] || [ -z "$element" ]; then
        log_error "Set name and element are required"
        return 1
    fi

    _nft_exec delete element "${table:-$(_nft_get_table)}" "$set_name" "{ $element }" 2>/dev/null || true
    return 0
}

# List set elements
# Usage: nft_set_list_elements <set_name> [table]
# Returns: Elements (one per line)
nft_set_list_elements() {
    local set_name="$1"
    local table="${2:-$(_nft_get_table)}"

    if [ -z "$set_name" ]; then
        log_error "Set name is required"
        return 1
    fi

    _nft_exec list set "${table:-$(_nft_get_table)}" "$set_name" 2>/dev/null | \
    awk '/elements = {/,/}/ {
        gsub(/[{},]/, " ")
        for (i=1; i<=NF; i++) {
            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || $i ~ /^[0-9a-f:]+$/) {
                print $i
            }
        }
    }'
}

# List all sets in table
# Usage: nft_set_list [table] [pattern]
# Returns: Set names (one per line)
nft_set_list() {
    local table="${1:-$(_nft_get_table)}"
    local pattern="$2"

    if [ -n "$pattern" ]; then
        _nft_exec list table "$table" 2>/dev/null | grep "set $pattern" | awk '{print $2}'
    else
        _nft_exec list table "$table" 2>/dev/null | grep "^[[:space:]]*set " | awk '{print $2}'
    fi
}

#=============================================================================
# Map Management API
#=============================================================================

# Check if map exists
# Usage: nft_map_exists <map_name> [table]
# Returns: 0 if exists, 1 if not
nft_map_exists() {
    local map_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$map_name" ]; then
        log_error "Map name is required"
        return 1
    fi

    _nft_exec list map "$table" "$map_name" >/dev/null 2>&1
}

# Create map
# Usage: nft_map_create <map_name> <key_type> <value_type> [table] [comment]
# Returns: 0 on success, 1 on failure
nft_map_create() {
    local map_name="$1"
    local key_type="$2"
    local value_type="$3"
    local table="$4"
    [ -z "$table" ] && table="$(_nft_get_table)"
    local comment="$5"

    if [ -z "$map_name" ] || [ -z "$key_type" ] || [ -z "$value_type" ]; then
        log_error "Map name, key type, and value type are required"
        return 1
    fi

    # Check if already exists
    if nft_map_exists "$map_name" "$table"; then
        log_debug "Map $map_name already exists"
        return 0
    fi

    # Build map definition
    local map_def="type $key_type : $value_type;"
    [ -n "$comment" ] && map_def="$map_def comment \"$comment\";"

    _nft_exec add map "${table:-$(_nft_get_table)}" "$map_name" "{ $map_def }"
}

# Delete map
# Usage: nft_map_delete <map_name> [table]
# Returns: 0 on success, 1 on failure
nft_map_delete() {
    local map_name="$1"
    local table="$2"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$map_name" ]; then
        log_error "Map name is required"
        return 1
    fi

    _nft_exec delete map "${table:-$(_nft_get_table)}" "$map_name" 2>/dev/null || true
    return 0
}

# Add element to map
# Usage: nft_map_add_element <map_name> <key> <value> [table]
# Returns: 0 on success, 1 on failure
nft_map_add_element() {
    local map_name="$1"
    local key="$2"
    local value="$3"
    local table="${4:-$(_nft_get_table)}"

    if [ -z "$map_name" ] || [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Map name, key, and value are required"
        return 1
    fi

    _nft_exec add element "${table:-$(_nft_get_table)}" "$map_name" "{ $key : $value }"
}

# Delete element from map
# Usage: nft_map_delete_element <map_name> <key> [table]
# Returns: 0 on success, 1 on failure
nft_map_delete_element() {
    local map_name="$1"
    local key="$2"
    local table="${3:-$(_nft_get_table)}"

    if [ -z "$map_name" ] || [ -z "$key" ]; then
        log_error "Map name and key are required"
        return 1
    fi

    _nft_exec delete element "${table:-$(_nft_get_table)}" "$map_name" "{ $key }" 2>/dev/null || true
    return 0
}

# Check if map contains key
# Usage: nft_map_has_key <map_name> <key> [table]
# Returns: 0 if key exists, 1 if not
nft_map_has_key() {
    local map_name="$1"
    local key="$2"
    local table="${3:-$(_nft_get_table)}"

    if [ -z "$map_name" ] || [ -z "$key" ]; then
        log_error "Map name and key are required"
        return 1
    fi

    _nft_exec list map "${table:-$(_nft_get_table)}" "$map_name" 2>/dev/null | grep -q "$key"
}

#=============================================================================
# Rule Management API
#=============================================================================

# Add rule to chain
# Usage: nft_rule_add <chain_name> <rule_spec> [table] [position]
# position: "insert" (default) or "add" (append)
# Returns: 0 on success, 1 on failure
nft_rule_add() {
    local chain_name="$1"
    local rule_spec="$2"
    local table="$3"
    [ -z "$table" ] && table="$(_nft_get_table)"
    local position="${4:-insert}"

    if [ -z "$chain_name" ] || [ -z "$rule_spec" ]; then
        log_error "Chain name and rule spec are required"
        return 1
    fi

    _nft_exec "$position" rule "${table:-$(_nft_get_table)}" "$chain_name" $rule_spec
}

# Delete rule by handle
# Usage: nft_rule_delete <chain_name> <handle> [table]
# Returns: 0 on success, 1 on failure
nft_rule_delete() {
    local chain_name="$1"
    local handle="$2"
    local table="$3"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$chain_name" ] || [ -z "$handle" ]; then
        log_error "Chain name and handle are required"
        return 1
    fi

    _nft_exec delete rule "${table:-$(_nft_get_table)}" "$chain_name" handle "$handle" 2>/dev/null || true
    return 0
}

# Delete rules by comment
# Usage: nft_rule_delete_by_comment <chain_name> <comment> [table]
# Returns: Number of rules deleted
nft_rule_delete_by_comment() {
    local chain_name="$1"
    local comment="$2"
    local table="$3"
    [ -z "$table" ] && table="$(_nft_get_table)"
    local count=0

    if [ -z "$chain_name" ] || [ -z "$comment" ]; then
        log_error "Chain name and comment are required"
        return 1
    fi

    local handles
    handles=$(_nft_exec list chain "${table:-$(_nft_get_table)}" "$chain_name" -a 2>/dev/null | \
        grep "$comment" | \
        awk '{print $NF}')

    for handle in $handles; do
        nft_rule_delete "$chain_name" "$handle" "$table"
        count=$((count + 1))
    done

    echo "$count"
}

# Check if rule exists (by comment)
# Usage: nft_rule_exists <chain_name> <comment> [table]
# Returns: 0 if exists, 1 if not
nft_rule_exists() {
    local chain_name="$1"
    local comment="$2"
    local table="$3"
    [ -z "$table" ] && table="$(_nft_get_table)"

    if [ -z "$chain_name" ] || [ -z "$comment" ]; then
        log_error "Chain name and comment are required"
        return 1
    fi

    _nft_exec list chain "${table:-$(_nft_get_table)}" "$chain_name" 2>/dev/null | grep -q "$comment"
}

#=============================================================================
# Counter Reading API
#=============================================================================

# Get counter from rule
# Usage: nft_counter_get <chain_name> <comment> [table]
# Returns: bytes packets (space-separated)
nft_counter_get() {
    local chain_name="$1"
    local comment="$2"
    local table="${3:-$(_nft_get_table)}"

    if [ -z "$chain_name" ] || [ -z "$comment" ]; then
        log_error "Chain name and comment are required"
        return 1
    fi

    _nft_exec list chain "${table:-$(_nft_get_table)}" "$chain_name" 2>/dev/null | \
    grep "$comment" | \
    grep "counter" | \
    sed -n 's/.*counter packets \([0-9]*\) bytes \([0-9]*\).*/\2 \1/p'
}

# Get all counters from chain
# Usage: nft_counter_list <chain_name> [table]
# Returns: comment bytes packets (tab-separated, one per line)
nft_counter_list() {
    local chain_name="$1"
    local table="${2:-$(_nft_get_table)}"

    if [ -z "$chain_name" ]; then
        log_error "Chain name is required"
        return 1
    fi

    _nft_exec list chain "$table" "$chain_name" 2>/dev/null | \
    grep "counter" | \
    while read -r line; do
        local comment=$(echo "$line" | sed -n 's/.*comment "\([^"]*\)".*/\1/p')
        local bytes=$(echo "$line" | sed -n 's/.*counter packets [0-9]* bytes \([0-9]*\).*/\1/p')
        local packets=$(echo "$line" | sed -n 's/.*counter packets \([0-9]*\) bytes.*/\1/p')

        [ -n "$comment" ] && [ -n "$bytes" ] && [ -n "$packets" ] && {
            echo "$comment	$bytes	$packets"
        }
    done
}

#=============================================================================
# High-level nft composition functions
# These provide the interface used by wrtbwmon binary, init script, and hotplug
#=============================================================================

# Map names for device dispatch
_NFT_MAP_V4="${_NFT_MAP_V4:-wrtbwmon_dispatch_v4}"
_NFT_MAP_V6="${_NFT_MAP_V6:-wrtbwmon_dispatch_v6}"

# Get chain name for device IP
# Usage: get_device_chain_name <ip>
# Returns: chain name (e.g. device_192_168_1_1)
get_device_chain_name() {
    local ip="$1"
    echo "device_$(echo "$ip" | tr '.:' '__')"
}

# Reverse: chain name back to IP address
# Handles both IPv4 (device_192_168_1_1 -> 192.168.1.1)
# and IPv6 (device_2001_db8__1 -> 2001:db8::1)
chain_name_to_ip() {
    local chain="$1"
    local stripped
    stripped=$(echo "$chain" | sed 's/^device_//')

    if echo "$stripped" | grep -q '__'; then
        # Could be IPv6 (double underscore = ::) or IPv4 with double-underscore edge case
        # Heuristic: if it contains only hex chars and underscores, treat as IPv6
        local no_underscores
        no_underscores=$(echo "$stripped" | tr '_' ':')
        # Collapse consecutive colons from double-underscores back to ::
        echo "$no_underscores" | sed 's/:::/::/g'
    else
        # IPv4: single underscores are dots
        echo "$stripped" | tr '_' '.'
    fi
}

# Initialize nftables verdict maps and dispatch rules
# Usage: nft_init
# Returns: 0 on success, 1 on failure
nft_init() {
    local table
    table="$(_nft_get_table)"

    log_info "Initializing nftables verdict maps in $table"

    # Check if nftables is available
    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) not found"
        return 1
    fi

    # Check if table exists
    if ! nft list table "$table" >/dev/null 2>&1; then
        log_error "Table $table does not exist (firewall4 not running?)"
        return 1
    fi

    # Create IPv4 verdict map for device dispatch
    if ! nft_map_exists "$_NFT_MAP_V4" "$table"; then
        nft_map_create "$_NFT_MAP_V4" "ipv4_addr" "verdict" "$table" "wrtbwmon device dispatch IPv4" || {
            log_error "Failed to create IPv4 verdict map"
            return 1
        }
        log_info "IPv4 verdict map created: $_NFT_MAP_V4"
    else
        log_debug "IPv4 verdict map already exists: $_NFT_MAP_V4"
    fi

    # Create IPv6 verdict map for device dispatch
    if ! nft_map_exists "$_NFT_MAP_V6" "$table"; then
        nft_map_create "$_NFT_MAP_V6" "ipv6_addr" "verdict" "$table" "wrtbwmon device dispatch IPv6" || {
            log_error "Failed to create IPv6 verdict map"
            return 1
        }
        log_info "IPv6 verdict map created: $_NFT_MAP_V6"
    else
        log_debug "IPv6 verdict map already exists: $_NFT_MAP_V6"
    fi

    # Setup dispatch rules in forward chain
    nft_setup_dispatch_rules || return 1

    log_info "nftables verdict maps initialized successfully"
    return 0
}

# Setup dispatch rules in forward chain (idempotent)
# Usage: nft_setup_dispatch_rules
# Returns: 0 on success, 1 on failure
nft_setup_dispatch_rules() {
    local table
    table="$(_nft_get_table)"

    log_info "Setting up dispatch rules in forward chain"

    # Check if all 4 dispatch rules exist
    local forward_chain
    forward_chain=$(nft list chain "$table" forward 2>/dev/null)
    local has_v4_up=$(echo "$forward_chain" | grep -c "wrtbwmon-dispatch-v4-up")
    local has_v4_down=$(echo "$forward_chain" | grep -c "wrtbwmon-dispatch-v4-down")
    local has_v6_up=$(echo "$forward_chain" | grep -c "wrtbwmon-dispatch-v6-up")
    local has_v6_down=$(echo "$forward_chain" | grep -c "wrtbwmon-dispatch-v6-down")

    if [ "$has_v4_up" -gt 0 ] && [ "$has_v4_down" -gt 0 ] && [ "$has_v6_up" -gt 0 ] && [ "$has_v6_down" -gt 0 ]; then
        log_debug "All 4 dispatch rules already exist"
        return 0
    fi

    # Remove any partial dispatch rules
    if [ "$has_v4_up" -gt 0 ] || [ "$has_v4_down" -gt 0 ] || [ "$has_v6_up" -gt 0 ] || [ "$has_v6_down" -gt 0 ]; then
        log_info "Removing incomplete dispatch rules"
        nft list chain "$table" forward -a 2>/dev/null | \
        grep "wrtbwmon-dispatch" | \
        awk '{print $NF}' | \
        while read handle; do
            nft delete rule "$table" forward handle "$handle" 2>/dev/null || true
        done
    fi

    # Add dispatch rules using verdict maps
    nft insert rule "$table" forward ip saddr vmap @"$_NFT_MAP_V4" comment \"wrtbwmon-dispatch-v4-up\" 2>/dev/null || {
        log_error "Failed to add IPv4 upload dispatch rule"
        return 1
    }
    nft insert rule "$table" forward ip daddr vmap @"$_NFT_MAP_V4" comment \"wrtbwmon-dispatch-v4-down\" 2>/dev/null || {
        log_error "Failed to add IPv4 download dispatch rule"
        return 1
    }
    nft insert rule "$table" forward ip6 saddr vmap @"$_NFT_MAP_V6" comment \"wrtbwmon-dispatch-v6-up\" 2>/dev/null || {
        log_error "Failed to add IPv6 upload dispatch rule"
        return 1
    }
    nft insert rule "$table" forward ip6 daddr vmap @"$_NFT_MAP_V6" comment \"wrtbwmon-dispatch-v6-down\" 2>/dev/null || {
        log_error "Failed to add IPv6 download dispatch rule"
        return 1
    }

    log_info "Dispatch rules added successfully (4 rules total)"
    return 0
}


# Cleanup all wrtbwmon nftables objects
# Usage: nft_cleanup
# Returns: 0 on success, 1 on failure
nft_cleanup() {
    local table
    table="$(_nft_get_table)"

    log_info "Cleaning up nftables objects"

    # Delete dispatch rules from forward chain
    nft list chain "$table" forward -a 2>/dev/null | \
    grep "wrtbwmon-dispatch" | \
    awk '{print $NF}' | \
    while read -r handle; do
        nft delete rule "$table" forward handle "$handle" 2>/dev/null || true
    done

    # Delete all device chains
    nft_chain_list "$table" "device_" | while read -r chain_name; do
        nft_chain_delete "$chain_name" "$table" 2>/dev/null || true
    done

    # Delete verdict maps
    nft_map_delete "$_NFT_MAP_V4" "$table" 2>/dev/null || {
        log_debug "IPv4 verdict map not found or already deleted"
    }
    nft_map_delete "$_NFT_MAP_V6" "$table" 2>/dev/null || {
        log_debug "IPv6 verdict map not found or already deleted"
    }

    log_info "Cleanup complete"
    return 0
}

# Get nftables statistics
# Usage: nft_stats
# Returns: Prints statistics to stdout
nft_stats() {
    local table
    table="$(_nft_get_table)"

    echo "=== nftables Statistics ==="
    echo ""

    # Count device chains
    local device_count
    device_count=$(nft_chain_list "$table" "device_" | wc -l)
    echo "Monitored devices: $device_count"

    # Count dispatch rules
    local dispatch_count
    dispatch_count=$(nft list chain "$table" forward 2>/dev/null | grep -c "wrtbwmon-dispatch" || echo "0")
    echo "Dispatch rules: $dispatch_count"

    # Counter stats from all device chains
    echo ""
    echo "Counter Statistics:"
    nft_chain_list "$table" "device_" | while read -r chain_name; do
        nft_counter_list "$chain_name" "$table"
    done | awk -F'\t' '{
        total_packets += $3
        total_bytes += $2
    }
    END {
        print "  Total packets: " total_packets
        print "  Total bytes: " total_bytes
        if (total_bytes > 1073741824) {
            printf "  Total traffic: %.2f GB\n", total_bytes/1073741824
        } else if (total_bytes > 1048576) {
            printf "  Total traffic: %.2f MB\n", total_bytes/1048576
        } else if (total_bytes > 1024) {
            printf "  Total traffic: %.2f KB\n", total_bytes/1024
        } else {
            printf "  Total traffic: %d B\n", total_bytes
        }
    }'

    echo ""
}

#=============================================================================
# Main function for testing
#=============================================================================

if [ "${0##*/}" = "chain_manager.sh" ]; then
    case "$1" in
        # Chain operations
        chain-exists)
            nft_chain_exists "$2" "$3"
            ;;
        chain-create)
            nft_chain_create "$2" "$3" "$4"
            ;;
        chain-delete)
            nft_chain_delete "$2" "$3"
            ;;
        chain-flush)
            nft_chain_flush "$2" "$3"
            ;;
        chain-list)
            nft_chain_list "$2" "$3"
            ;;
        chain-get)
            nft_chain_get "$2" "$3"
            ;;

        # Set operations
        set-exists)
            nft_set_exists "$2" "$3"
            ;;
        set-create)
            nft_set_create "$2" "$3" "$4" "$5" "$6"
            ;;
        set-delete)
            nft_set_delete "$2" "$3"
            ;;
        set-add-element)
            nft_set_add_element "$2" "$3" "$4"
            ;;
        set-delete-element)
            nft_set_delete_element "$2" "$3" "$4"
            ;;
        set-list-elements)
            nft_set_list_elements "$2" "$3"
            ;;
        set-list)
            nft_set_list "$2" "$3"
            ;;

        # Map operations
        map-exists)
            nft_map_exists "$2" "$3"
            ;;
        map-create)
            nft_map_create "$2" "$3" "$4" "$5" "$6"
            ;;
        map-delete)
            nft_map_delete "$2" "$3"
            ;;
        map-add-element)
            nft_map_add_element "$2" "$3" "$4" "$5"
            ;;
        map-delete-element)
            nft_map_delete_element "$2" "$3" "$4"
            ;;
        map-has-key)
            nft_map_has_key "$2" "$3" "$4"
            ;;

        # Rule operations
        rule-add)
            nft_rule_add "$2" "$3" "$4" "$5"
            ;;
        rule-delete)
            nft_rule_delete "$2" "$3" "$4"
            ;;
        rule-delete-by-comment)
            nft_rule_delete_by_comment "$2" "$3" "$4"
            ;;
        rule-exists)
            nft_rule_exists "$2" "$3" "$4"
            ;;

        # Counter operations
        counter-get)
            nft_counter_get "$2" "$3" "$4"
            ;;
        counter-list)
            nft_counter_list "$2" "$3"
            ;;

        *)
            echo "Usage: $0 <operation> [args...]"
            echo ""
            echo "Chain Operations:"
            echo "  chain-exists <name> [table]"
            echo "  chain-create <name> [table] [hook_spec]"
            echo "  chain-delete <name> [table]"
            echo "  chain-flush <name> [table]"
            echo "  chain-list [table] [pattern]"
            echo "  chain-get <name> [table]"
            echo ""
            echo "Set Operations:"
            echo "  set-exists <name> [table]"
            echo "  set-create <name> <type> [table] [flags] [comment]"
            echo "  set-delete <name> [table]"
            echo "  set-add-element <name> <element> [table]"
            echo "  set-delete-element <name> <element> [table]"
            echo "  set-list-elements <name> [table]"
            echo "  set-list [table] [pattern]"
            echo ""
            echo "Map Operations:"
            echo "  map-exists <name> [table]"
            echo "  map-create <name> <key_type> <value_type> [table] [comment]"
            echo "  map-delete <name> [table]"
            echo "  map-add-element <name> <key> <value> [table]"
            echo "  map-delete-element <name> <key> [table]"
            echo "  map-has-key <name> <key> [table]"
            echo ""
            echo "Rule Operations:"
            echo "  rule-add <chain> <rule_spec> [table] [position]"
            echo "  rule-delete <chain> <handle> [table]"
            echo "  rule-delete-by-comment <chain> <comment> [table]"
            echo "  rule-exists <chain> <comment> [table]"
            echo ""
            echo "Counter Operations:"
            echo "  counter-get <chain> <comment> [table]"
            echo "  counter-list <chain> [table]"
            exit 1
            ;;
    esac
fi
