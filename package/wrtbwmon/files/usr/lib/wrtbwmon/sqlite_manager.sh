#!/bin/sh
# SQLite Database Manager for wrtbwmon
# Provides atomic operations for traffic database management

# Library paths
LIB_DIR="/usr/lib/wrtbwmon"
[ -d "/usr/sbin/../lib/wrtbwmon" ] && LIB_DIR="/usr/sbin/../lib/wrtbwmon"

# Source core libraries
. "$LIB_DIR/logger.sh" || { echo "ERROR: logger.sh not found" >&2; return 1; }
. "$LIB_DIR/error_handler.sh" || { echo "ERROR: error_handler.sh not found" >&2; return 1; }
. "$LIB_DIR/config.sh" || { echo "ERROR: config.sh not found" >&2; return 1; }
. "$LIB_DIR/retry.sh" || { echo "ERROR: retry.sh not found" >&2; return 1; }

# Source validation library
if [ -f "$LIB_DIR/validation.sh" ]; then
    . "$LIB_DIR/validation.sh"
else
    log_error "validation.sh not found"
    return 1
fi

# Initialize library logging (only if not already initialized)
if [ -z "$_LOGGER_INITIALIZED" ]; then
    log_init "wrtbwmon-sqlite" "${LOG_LEVEL:-info}"
fi

# Initialize SQLite database with schema
# Usage: sqlite_init [db_file]
# Parameters:
#   $1 - Database file path (optional, defaults to config DB_FILE)
# Returns: 0 on success, 1 on failure
# Side effects:
#   - Creates database directory if needed
#   - Creates tables and indexes
#   - Adds migration columns if needed
sqlite_init() {
    local db_file="${1:-$(config_get "DB_FILE")}"
    local db_dir
    db_dir=$(dirname "$db_file")

    log_info "Initializing SQLite database: $db_file"

    # Create directory if needed
    if [ ! -d "$db_dir" ]; then
        if ! mkdir -p "$db_dir" 2>/dev/null; then
            log_error "Failed to create directory: $db_dir"
            return 1
        fi
    fi

    # Create database with schema. `if ! cmd; then ERROR; else OK` is the
    # correct shape — we previously had the branches swapped, which fired
    # "Failed to create database schema" on every successful run.
    if ! retry_db 5 sqlite3 "$db_file" <<'SQL' 2>/dev/null
-- Device registry
CREATE TABLE IF NOT EXISTS devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT UNIQUE NOT NULL COLLATE NOCASE,
    ip TEXT,
    hostname TEXT,
    first_seen INTEGER NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    CHECK (length(mac) >= 12),
    CHECK (first_seen > 0)
);

-- Daily traffic per device (one row per device per day, no rotation needed)
CREATE TABLE IF NOT EXISTS traffic_daily (
    device_id INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    bytes_down INTEGER NOT NULL DEFAULT 0,
    bytes_up INTEGER NOT NULL DEFAULT 0,
    last_seen INTEGER,
    last_counter_down INTEGER NOT NULL DEFAULT 0,
    last_counter_up INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, date)
);

CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices(mac COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_td_date ON traffic_daily(date DESC);
CREATE INDEX IF NOT EXISTS idx_td_device_date ON traffic_daily(device_id, date DESC);

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
SQL
    then
        log_error "Failed to create database schema"
        return 1
    fi

    # Migration: add ip column to existing databases (idempotent — fails silently if already present)
    sqlite3 "$db_file" "ALTER TABLE devices ADD COLUMN ip TEXT;" 2>/dev/null || true

    log_info "Database initialized successfully"
    return 0
}

# Update device traffic (UPSERT operation)
# Usage: sqlite_update_device <mac> <ip> <interface> <bytes_down> <bytes_up> [db_file]
# Parameters:
#   $1 - MAC address (required)
#   $2 - IP address (required)
#   $3 - Interface name (default: br-lan)
#   $4 - Bytes downloaded (required)
#   $5 - Bytes uploaded (required)
#   $6 - Database file path (optional)
# Returns: 0 on success, 1 on failure
sqlite_update_device() {
    local mac="$1"
    local ip="$2"
    local iface="${3:-br-lan}"
    local down="$4"
    local up="$5"
    local db_file="${6:-$DB_FILE}"
    local now=$(date +%s)

    # Validate inputs
    if ! validate_mac "$mac"; then
        log_error "Invalid MAC address: $mac"
        return 1
    fi

    if [ -n "$ip" ] && ! validate_ip "$ip"; then
        log_error "Invalid IP address: $ip"
        return 1
    fi

    if ! validate_interface "$iface"; then
        log_error "Invalid interface: $iface"
        return 1
    fi

    if ! validate_positive_int "$down" || ! validate_positive_int "$up"; then
        log_error "Invalid byte counts: down=$down up=$up"
        return 1
    fi

    # SQL-escape inputs (defense in depth)
    mac=$(sql_escape "$mac")
    ip=$(sql_escape "$ip")
    iface=$(sql_escape "$iface")

    # Get hostname from various sources
    local hostname=""

    # Try UCI static DHCP assignments first
    hostname=$(uci show dhcp 2>/dev/null | grep -i "mac='$mac'" -B1 | grep "\.name=" | sed "s/.*='\(.*\)'/\1/" | head -1)

    # Try DHCP leases if no static assignment
    if [ -z "$hostname" ] && [ -f /tmp/dhcp.leases ]; then
        hostname=$(grep -i "$mac" /tmp/dhcp.leases | awk '{print $4}' | head -1)
    fi

    # Try reverse DNS lookup on IP
    if [ -z "$hostname" ] && [ -n "$ip" ]; then
        hostname=$(nslookup "$ip" 2>/dev/null | grep "name =" | awk '{print $NF}' | sed 's/\.$//' | head -1)
    fi

    # SQL-escape hostname
    if [ -n "$hostname" ]; then
        hostname=$(sql_escape "$hostname")
    fi

    # Check if counters changed to decide whether to update last_seen
    local last_seen_val="$now"
    local prev_counters
    prev_counters=$(sqlite3 "$db_file" "SELECT COALESCE(last_counter_down, 0), COALESCE(last_counter_up, 0) FROM traffic WHERE device_id = (SELECT id FROM devices WHERE mac = '$mac') ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null)
    if [ -n "$prev_counters" ]; then
        local prev_down=$(echo "$prev_counters" | cut -d'|' -f1)
        local prev_up=$(echo "$prev_counters" | cut -d'|' -f2)
        if [ "$down" = "$prev_down" ] && [ "$up" = "$prev_up" ]; then
            # No traffic change - keep existing last_seen
            last_seen_val=$(sqlite3 "$db_file" "SELECT last_seen FROM devices WHERE mac = '$mac';" 2>/dev/null)
        fi
    fi

    # Execute UPSERT with retry logic and proper transaction isolation
    local retry_count=0
    local max_retries=5
    local retry_delay=1

    while [ $retry_count -lt $max_retries ]; do
        if sqlite3 -batch "$db_file" <<SQL >/dev/null 2>/dev/null
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

-- Use IMMEDIATE transaction for write lock
BEGIN IMMEDIATE;

-- Insert or update device
INSERT INTO devices (mac, hostname, first_seen, last_seen)
VALUES ('$mac', $([ -n "$hostname" ] && echo "'$hostname'" || echo "NULL"), $now, $now)
ON CONFLICT(mac) DO UPDATE SET
    hostname = COALESCE(excluded.hostname, hostname),
    last_seen = $last_seen_val,
    updated_at = $now;

-- Insert traffic record with counter reset detection and delta computation
-- delta = actual traffic since last update (handles nft counter resets)
WITH last_record AS (
    SELECT bytes_down, bytes_up, last_counter_down, last_counter_up
    FROM traffic
    WHERE device_id = (SELECT id FROM devices WHERE mac = '$mac')
    ORDER BY timestamp DESC
    LIMIT 1
),
delta_calc AS (
    SELECT
        COALESCE(
            (SELECT CASE
                WHEN $down < last_counter_down AND (last_counter_down - $down) > last_counter_down / 2 THEN $down
                WHEN $down < last_counter_down THEN $down
                WHEN $down > last_counter_down THEN $down - last_counter_down
                ELSE 0
            END FROM last_record),
            $down
        ) as dl_delta,
        COALESCE(
            (SELECT CASE
                WHEN $up < last_counter_up AND (last_counter_up - $up) > last_counter_up / 2 THEN $up
                WHEN $up < last_counter_up THEN $up
                WHEN $up > last_counter_up THEN $up - last_counter_up
                ELSE 0
            END FROM last_record),
            $up
        ) as ul_delta
)
INSERT INTO traffic (device_id, timestamp, ip, interface, bytes_down, bytes_up, download_delta, upload_delta, total_delta, last_counter_down, last_counter_up)
SELECT
    d.id,
    $now,
    NULLIF('$ip', ''),
    '$iface',
    COALESCE(
        (SELECT
            CASE
                WHEN $down < last_counter_down THEN bytes_down + $down
                WHEN $down > last_counter_down THEN bytes_down + ($down - last_counter_down)
                ELSE bytes_down
            END
        FROM last_record),
        $down
    ),
    COALESCE(
        (SELECT
            CASE
                WHEN $up < last_counter_up THEN bytes_up + $up
                WHEN $up > last_counter_up THEN bytes_up + ($up - last_counter_up)
                ELSE bytes_up
            END
        FROM last_record),
        $up
    ),
    dc.dl_delta,
    dc.ul_delta,
    dc.dl_delta + dc.ul_delta,
    $down,
    $up
FROM devices d, delta_calc dc
WHERE d.mac = '$mac'
ON CONFLICT (device_id, timestamp) DO UPDATE SET
    bytes_down = excluded.bytes_down,
    bytes_up = excluded.bytes_up,
    download_delta = excluded.download_delta,
    upload_delta = excluded.upload_delta,
    total_delta = excluded.total_delta,
    last_counter_down = excluded.last_counter_down,
    last_counter_up = excluded.last_counter_up;

COMMIT;
SQL
        then
            return 0
        fi

        # Check if it's a lock error
        if [ $? -eq 5 ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log "Database locked, retrying ($retry_count/$max_retries)..."
                sleep $retry_delay
                continue
            fi
        fi

        log_error "Failed to update device: $mac"
        return 1
    done

    log_error "Failed to update device after $max_retries retries: $mac"
    return 1
}

# Get all device IPs for nftables set rebuild
sqlite_get_devices() {
    local db_file="${1:-$(config_get "DB_FILE")}"

    if [ ! -f "$db_file" ]; then
        log_error "Database not found: $db_file"
        return 1
    fi

    retry_db 5 sqlite3 "$db_file" "SELECT DISTINCT ip FROM devices WHERE ip IS NOT NULL AND ip != '' ORDER BY ip;" 2>/dev/null
}

# Get all device MACs
sqlite_get_macs() {
    local db_file="${1:-$(config_get "DB_FILE")}"

    if [ ! -f "$db_file" ]; then
        log_error "Database not found: $db_file"
        return 1
    fi

    retry_db 5 sqlite3 "$db_file" "SELECT mac FROM devices ORDER BY updated_at DESC;" 2>/dev/null
}

# Cleanup old devices (remove inactive devices older than N days)
sqlite_cleanup_old() {
    local days="${1:-90}"
    local db_file="${2:-$(config_get "DB_FILE")}"
    case "$days" in
        ''|*[!0-9]*) days=90 ;;
    esac

    log_info "Cleaning up devices inactive for $days days"

    # Delete old traffic records
    local deleted
    deleted=$(retry_db 5 sqlite3 "$db_file" <<SQL 2>/dev/null
PRAGMA foreign_keys = ON;
DELETE FROM traffic_daily WHERE date < date('now', 'localtime', '-$days days');
SELECT changes();
SQL
)

    log_info "Deleted $deleted old traffic records"

    # Delete devices with no traffic
    local deleted_devices
    deleted_devices=$(retry_db 5 sqlite3 "$db_file" <<SQL 2>/dev/null
DELETE FROM devices
WHERE id NOT IN (SELECT DISTINCT device_id FROM traffic_daily);
SELECT changes();
SQL
)

    log_info "Deleted $deleted_devices orphaned devices"

    # Vacuum to reclaim space (with retry logic)
    local vacuum_retries=0
    local max_vacuum_retries=3
    while [ $vacuum_retries -lt $max_vacuum_retries ]; do
        if retry_db 5 sqlite3 "$db_file" "PRAGMA busy_timeout = 5000; VACUUM;" 2>/dev/null; then
            log_info "VACUUM completed successfully"
            break
        fi

        vacuum_retries=$((vacuum_retries + 1))
        if [ $vacuum_retries -lt $max_vacuum_retries ]; then
            log_warn "VACUUM failed, retrying ($vacuum_retries/$max_vacuum_retries)..."
            sleep 2
        else
            log_error "VACUUM failed after $max_vacuum_retries attempts (database may be locked)"
        fi
    done

    log_info "Cleanup complete"
    return 0
}

# Export database to CSV format (for compatibility/backup)
sqlite_export_csv() {
    local output_file="$1"
    local db_file="${2:-$(config_get "DB_FILE")}"

    if [ -z "$output_file" ]; then
        log_error "Output file not specified"
        return 1
    fi

    log_info "Exporting database to CSV: $output_file"

    retry_db 5 sqlite3 -header -csv "$db_file" "SELECT d.mac, COALESCE(d.ip, '') AS ip, '' AS interface, SUM(COALESCE(td.bytes_down, 0)) AS download, SUM(COALESCE(td.bytes_up, 0)) AS upload, SUM(COALESCE(td.bytes_down, 0) + COALESCE(td.bytes_up, 0)) AS total, datetime(d.first_seen, 'unixepoch', 'localtime') AS first_seen, datetime(MAX(td.last_seen), 'unixepoch', 'localtime') AS last_seen FROM devices d JOIN traffic_daily td ON td.device_id = d.id GROUP BY d.id, d.mac, d.ip, d.first_seen ORDER BY total DESC;" > "$output_file" 2>/dev/null || {
        log_error "Export failed"
        return 1
    }

    log_info "Export complete: $output_file"
    return 0
}

# Get database statistics
sqlite_stats() {
    local db_file="${1:-$(config_get "DB_FILE")}"

    if [ ! -f "$db_file" ]; then
        echo "Database not found: $db_file"
        return 1
    fi

    echo "=== SQLite Database Statistics ==="
    echo ""

    # Device count
    local device_count
    device_count=$(retry_db 5 sqlite3 "$db_file" "SELECT COUNT(*) FROM devices;" 2>/dev/null)
    echo "Devices: $device_count"

    # Traffic record count
    local traffic_count
    traffic_count=$(retry_db 5 sqlite3 "$db_file" "SELECT COUNT(*) FROM traffic_daily;" 2>/dev/null)
    echo "Traffic daily records: $traffic_count"

    # Database size
    local db_size
    db_size=$(du -h "$db_file" 2>/dev/null | cut -f1)
    echo "Database size: $db_size"

    # Date range
    local oldest
    oldest=$(retry_db 5 sqlite3 "$db_file" "SELECT MIN(date) FROM traffic_daily;" 2>/dev/null)
    local newest
    newest=$(retry_db 5 sqlite3 "$db_file" "SELECT MAX(date) FROM traffic_daily;" 2>/dev/null)
    echo "Date range: $oldest to $newest"

    # Schema version
    local version
    version=$(retry_db 5 sqlite3 "$db_file" "SELECT CASE WHEN EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='traffic_daily') THEN 'daily' ELSE 'unknown' END;" 2>/dev/null)
    echo "Schema version: $version"

    echo ""
}

# Verify database integrity
sqlite_verify() {
    local db_file="${1:-$(config_get "DB_FILE")}"

    log_info "Verifying database integrity: $db_file"

    if [ ! -f "$db_file" ]; then
        log_error "Database not found: $db_file"
        return 1
    fi

    # Run integrity check
    local result
    result=$(retry_db 5 sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null)

    if [ "$result" = "ok" ]; then
        log_info "Database integrity check: OK"
        return 0
    else
        log_error "Database integrity check FAILED: $result"
        return 1
    fi
}

# Backup database
sqlite_backup() {
    local db_file="${1:-$(config_get "DB_FILE")}"
    local backup_dir="${2:-$(dirname "$db_file")/backups}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/traffic_${timestamp}.db"

    log_info "Creating database backup: $backup_file"

    # Create backup directory
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        log_error "Failed to create backup directory: $backup_dir"
        return 1
    fi

    # Copy database
    if ! cp "$db_file" "$backup_file" 2>/dev/null; then
        log_error "Backup failed"
        return 1
    fi

    # Compress backup
    gzip "$backup_file" 2>/dev/null && backup_file="${backup_file}.gz"

    log_info "Backup complete: $backup_file"
    echo "$backup_file"
    return 0
}

# Main function for testing
if [ "${0##*/}" = "sqlite_manager.sh" ]; then
    case "$1" in
        init)
            sqlite_init "$2"
            ;;
        update)
            sqlite_update_device "$2" "$3" "$4" "$5" "$6"
            ;;
        devices)
            sqlite_get_devices "$2"
            ;;
        macs)
            sqlite_get_macs "$2"
            ;;
        cleanup)
            sqlite_cleanup_old "$2" "$3"
            ;;
        export)
            sqlite_export_csv "$2" "$3"
            ;;
        stats)
            sqlite_stats "$2"
            ;;
        verify)
            sqlite_verify "$2"
            ;;
        backup)
            sqlite_backup "$2" "$3"
            ;;
        *)
            echo "Usage: $0 {init|update|devices|macs|cleanup|export|stats|verify|backup} [args...]"
            exit 1
            ;;
    esac
fi
