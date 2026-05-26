#!/bin/sh
# Unified Logging Library for wrtbwmon
# Provides consistent logging across all scripts with log levels and structured output

# Log levels (numeric for comparison)
# Protect against multiple sourcing
if [ -z "$LOG_LEVEL_DEBUG" ]; then
    readonly LOG_LEVEL_DEBUG=0
    readonly LOG_LEVEL_INFO=1
    readonly LOG_LEVEL_WARN=2
    readonly LOG_LEVEL_ERROR=3
    readonly LOG_LEVEL_FATAL=4
fi

# Default configuration (can be overridden by environment)
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_TAG="${LOG_TAG:-wrtbwmon}"
LOG_TO_SYSLOG="${LOG_TO_SYSLOG:-1}"
LOG_TO_STDOUT="${LOG_TO_STDOUT:-0}"
LOG_TO_FILE="${LOG_TO_FILE:-}"

# Convert log level name to numeric value
_log_level_to_num() {
    case "$1" in
        debug) echo $LOG_LEVEL_DEBUG ;;
        info)  echo $LOG_LEVEL_INFO ;;
        warn)  echo $LOG_LEVEL_WARN ;;
        error) echo $LOG_LEVEL_ERROR ;;
        fatal) echo $LOG_LEVEL_FATAL ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# Get current log level as number
_get_current_level() {
    _log_level_to_num "$LOG_LEVEL"
}

# Check if message should be logged based on level
_should_log() {
    local msg_level=$1
    local current_level=$(_get_current_level)
    [ "$msg_level" -ge "$current_level" ]
}

# Format log message with timestamp and context
_format_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Add script name if available
    local script_name="${0##*/}"

    echo "[$timestamp] [$level] [$script_name] $message"
}

# Internal logging function
_log() {
    local level_name="$1"
    local level_num="$2"
    local syslog_priority="$3"
    shift 3
    local message="$*"

    # Check if we should log this level
    if ! _should_log "$level_num"; then
        return 0
    fi

    local formatted_msg=$(_format_message "$level_name" "$message")

    # Log to syslog
    if [ "$LOG_TO_SYSLOG" = "1" ]; then
        logger -t "$LOG_TAG" -p "$syslog_priority" "$message"
    fi

    # Log to stdout/stderr
    if [ "$LOG_TO_STDOUT" = "1" ]; then
        if [ "$level_num" -ge "$LOG_LEVEL_ERROR" ]; then
            echo "$formatted_msg" >&2
        else
            echo "$formatted_msg"
        fi
    fi

    # Log to file
    if [ -n "$LOG_TO_FILE" ]; then
        echo "$formatted_msg" >> "$LOG_TO_FILE"
    fi
}

# Public logging functions

# Debug: Detailed information for diagnosing problems
# Usage: log_debug "Variable value: $var"
log_debug() {
    _log "DEBUG" "$LOG_LEVEL_DEBUG" "user.debug" "$@"
}

# Info: General informational messages
# Usage: log_info "Processing started"
log_info() {
    _log "INFO" "$LOG_LEVEL_INFO" "user.info" "$@"
}

# Warn: Warning messages for potentially harmful situations
# Usage: log_warn "Disk space low"
log_warn() {
    _log "WARN" "$LOG_LEVEL_WARN" "user.warning" "$@"
}

# Error: Error messages for failures that don't stop execution
# Usage: log_error "Failed to connect to database"
log_error() {
    _log "ERROR" "$LOG_LEVEL_ERROR" "user.err" "$@"
}

# Fatal: Critical errors that require script termination
# Usage: log_fatal "Configuration file not found"
# Note: This function exits with code 1
log_fatal() {
    _log "FATAL" "$LOG_LEVEL_FATAL" "user.crit" "$@"
    exit 1
}

# Convenience function for backward compatibility
# Usage: log "message"
log() {
    log_info "$@"
}

# Set log level dynamically
# Usage: log_set_level "debug"
log_set_level() {
    local new_level="$1"
    case "$new_level" in
        debug|info|warn|error|fatal)
            LOG_LEVEL="$new_level"
            log_debug "Log level changed to: $new_level"
            ;;
        *)
            log_error "Invalid log level: $new_level (valid: debug, info, warn, error, fatal)"
            return 1
            ;;
    esac
}

# Enable/disable syslog output
# Usage: log_set_syslog 1  # enable
log_set_syslog() {
    LOG_TO_SYSLOG="$1"
}

# Enable/disable stdout output
# Usage: log_set_stdout 1  # enable
log_set_stdout() {
    LOG_TO_STDOUT="$1"
}

# Set log file path
# Usage: log_set_file "/var/log/wrtbwmon.log"
log_set_file() {
    LOG_TO_FILE="$1"
    if [ -n "$LOG_TO_FILE" ]; then
        # Ensure directory exists
        local log_dir=$(dirname "$LOG_TO_FILE")
        if [ ! -d "$log_dir" ]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                log_error "Failed to create log directory: $log_dir"
                LOG_TO_FILE=""
                return 1
            }
        fi
        log_debug "Logging to file: $LOG_TO_FILE"
    fi
}

# Log with context (file and line number)
# Usage: log_context "$LINENO" "Error occurred"
log_context() {
    local line_no="$1"
    shift
    local message="$*"
    log_error "Line $line_no: $message"
}

# Log execution time of a command
# Usage: log_timed "description" command args...
log_timed() {
    local description="$1"
    shift
    local start_time=$(date +%s)

    log_debug "Starting: $description"
    "$@"
    local exit_code=$?

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        log_debug "Completed: $description (${duration}s)"
    else
        log_error "Failed: $description (${duration}s, exit code: $exit_code)"
    fi

    return $exit_code
}

# Initialize logging with configuration
# Usage: log_init "script-name" "info" "/var/log/script.log"
log_init() {
    local tag="${1:-wrtbwmon}"
    local level="${2:-info}"
    local file="${3:-}"

    LOG_TAG="$tag"
    log_set_level "$level"

    if [ -n "$file" ]; then
        log_set_file "$file"
    fi

    log_debug "Logging initialized: tag=$LOG_TAG, level=$LOG_LEVEL"
    _LOGGER_INITIALIZED=1
}

# Test function to verify logging works
_log_test() {
    echo "=== Logger Test ==="
    log_set_stdout 1
    log_set_level "debug"

    log_debug "This is a debug message"
    log_info "This is an info message"
    log_warn "This is a warning message"
    log_error "This is an error message"

    echo ""
    echo "Changing log level to 'warn'..."
    log_set_level "warn"

    log_debug "This debug should NOT appear"
    log_info "This info should NOT appear"
    log_warn "This warning SHOULD appear"
    log_error "This error SHOULD appear"

    echo ""
    echo "=== Test Complete ==="
}

# Run test if executed directly
if [ "${0##*/}" = "logger.sh" ]; then
    case "${1:-}" in
        test)
            _log_test
            ;;
        *)
            echo "Usage: $0 test"
            echo ""
            echo "Or source this file in your script:"
            echo "  . /usr/lib/wrtbwmon/logger.sh"
            echo ""
            echo "Available functions:"
            echo "  log_debug    - Debug messages"
            echo "  log_info     - Informational messages"
            echo "  log_warn     - Warning messages"
            echo "  log_error    - Error messages"
            echo "  log_fatal    - Fatal errors (exits script)"
            echo "  log_init     - Initialize logging"
            echo "  log_set_level - Change log level"
            echo "  log_timed    - Time command execution"
            ;;
    esac
fi
