#!/bin/sh
# Error Handling Library for wrtbwmon
# Provides centralized error handling, cleanup, and graceful degradation

# Error codes (following standard conventions)
# Protect against multiple sourcing
if [ -z "$E_SUCCESS" ]; then
    readonly E_SUCCESS=0
    readonly E_GENERAL=1
    readonly E_INVALID_ARGS=2
    readonly E_DB_ERROR=3
    readonly E_NFT_ERROR=4
    readonly E_LOCK_ERROR=5
    readonly E_PERMISSION=6
    readonly E_NOT_FOUND=7
    readonly E_TIMEOUT=8
    readonly E_NETWORK=9
    readonly E_CONFIG=10
fi

# Cleanup handlers (array of functions to call on exit)
_CLEANUP_HANDLERS=""

# Error context
_ERROR_CONTEXT=""

# Source logger if available
if [ -f "/usr/lib/wrtbwmon/logger.sh" ]; then
    . /usr/lib/wrtbwmon/logger.sh
elif [ -f "$(dirname "$0")/logger.sh" ]; then
    . "$(dirname "$0")/logger.sh"
else
    # Fallback logging if logger not available
    log_error() { echo "ERROR: $*" >&2; }
    log_warn() { echo "WARN: $*" >&2; }
    log_info() { echo "INFO: $*"; }
    log_debug() { :; }
    log_fatal() { echo "FATAL: $*" >&2; exit 1; }
fi

# Register a cleanup handler
# Usage: error_register_cleanup "cleanup_function"
error_register_cleanup() {
    local handler="$1"
    if [ -z "$_CLEANUP_HANDLERS" ]; then
        _CLEANUP_HANDLERS="$handler"
    else
        _CLEANUP_HANDLERS="$_CLEANUP_HANDLERS $handler"
    fi
    log_debug "Registered cleanup handler: $handler"
}

# Execute all cleanup handlers
_error_run_cleanup() {
    if [ -n "$_CLEANUP_HANDLERS" ]; then
        log_debug "Running cleanup handlers..."
        for handler in $_CLEANUP_HANDLERS; do
            if type "$handler" >/dev/null 2>&1; then
                log_debug "Executing cleanup: $handler"
                $handler || log_warn "Cleanup handler failed: $handler"
            fi
        done
    fi
}

# Set error context (for better error messages)
# Usage: error_set_context "Processing device: aa:bb:cc:dd:ee:ff"
error_set_context() {
    _ERROR_CONTEXT="$*"
    log_debug "Error context set: $_ERROR_CONTEXT"
}

# Clear error context
error_clear_context() {
    _ERROR_CONTEXT=""
}

# Get error message for error code
error_get_message() {
    local code=$1
    case $code in
        $E_SUCCESS)       echo "Success" ;;
        $E_GENERAL)       echo "General error" ;;
        $E_INVALID_ARGS)  echo "Invalid arguments" ;;
        $E_DB_ERROR)      echo "Database error" ;;
        $E_NFT_ERROR)     echo "nftables error" ;;
        $E_LOCK_ERROR)    echo "Lock/busy error" ;;
        $E_PERMISSION)    echo "Permission denied" ;;
        $E_NOT_FOUND)     echo "Not found" ;;
        $E_TIMEOUT)       echo "Timeout" ;;
        $E_NETWORK)       echo "Network error" ;;
        $E_CONFIG)        echo "Configuration error" ;;
        *)                echo "Unknown error ($code)" ;;
    esac
}

# Error trap handler
_error_trap_handler() {
    local exit_code=$?
    local line_no=$1

    # Don't trigger on successful exit
    if [ $exit_code -eq 0 ]; then
        return 0
    fi

    local error_msg=$(error_get_message $exit_code)

    if [ -n "$_ERROR_CONTEXT" ]; then
        log_error "Error at line $line_no: $error_msg (exit code: $exit_code)"
        log_error "Context: $_ERROR_CONTEXT"
    else
        log_error "Error at line $line_no: $error_msg (exit code: $exit_code)"
    fi

    # Run cleanup handlers
    _error_run_cleanup

    # Exit with the original error code
    exit $exit_code
}

# Exit trap handler (for normal exits)
_error_exit_handler() {
    local exit_code=$?

    # Run cleanup handlers on normal exit too
    _error_run_cleanup

    exit $exit_code
}

# Enable error trapping
# Usage: error_enable_trap
error_enable_trap() {
    # Enable error exit
    set -e

    # Enable error trap inheritance
    set -E

    # Set up error trap
    trap '_error_trap_handler ${LINENO}' ERR

    # Set up exit trap
    trap '_error_exit_handler' EXIT INT TERM

    log_debug "Error trapping enabled"
}

# Disable error trapping
# Usage: error_disable_trap
error_disable_trap() {
    set +e
    set +E
    trap - ERR EXIT INT TERM
    log_debug "Error trapping disabled"
}

# Execute command with error handling
# Usage: error_exec "description" command args...
# Returns: Command exit code
error_exec() {
    local description="$1"
    shift

    log_debug "Executing: $description"
    error_set_context "$description"

    "$@"
    local exit_code=$?

    error_clear_context

    if [ $exit_code -ne 0 ]; then
        log_error "Failed: $description (exit code: $exit_code)"
        return $exit_code
    fi

    log_debug "Success: $description"
    return 0
}

# Execute command with retry on failure
# Usage: error_retry 3 "description" command args...
# Returns: Command exit code
error_retry() {
    local max_attempts=$1
    local description="$2"
    shift 2

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $description"

        if "$@"; then
            log_debug "Success on attempt $attempt: $description"
            return 0
        fi

        local exit_code=$?

        if [ $attempt -lt $max_attempts ]; then
            log_warn "Attempt $attempt failed: $description (exit code: $exit_code), retrying..."
            sleep 1
            attempt=$((attempt + 1))
        else
            log_error "All $max_attempts attempts failed: $description"
            return $exit_code
        fi
    done
}

# Check if command succeeded, exit with error if not
# Usage: error_check $? "Failed to connect to database"
error_check() {
    local exit_code=$1
    local message="$2"

    if [ $exit_code -ne 0 ]; then
        if [ -n "$_ERROR_CONTEXT" ]; then
            log_fatal "$message (exit code: $exit_code, context: $_ERROR_CONTEXT)"
        else
            log_fatal "$message (exit code: $exit_code)"
        fi
    fi
}

# Assert condition is true, exit if false
# Usage: error_assert [ -f "$file" ] "File not found: $file"
error_assert() {
    if ! "$@"; then
        shift $(($# - 1))
        local message="$1"
        log_fatal "Assertion failed: $message"
    fi
}

# Require command exists, exit if not
# Usage: error_require_command "nft" "nftables not installed"
error_require_command() {
    local command="$1"
    local message="${2:-Command not found: $command}"

    if ! command -v "$command" >/dev/null 2>&1; then
        log_fatal "$message"
    fi
}

# Require file exists, exit if not
# Usage: error_require_file "/etc/config.conf" "Configuration file not found"
error_require_file() {
    local file="$1"
    local message="${2:-File not found: $file}"

    if [ ! -f "$file" ]; then
        log_fatal "$message"
    fi
}

# Require directory exists, exit if not
# Usage: error_require_dir "/etc/wrtbwmon" "Data directory not found"
error_require_dir() {
    local dir="$1"
    local message="${2:-Directory not found: $dir}"

    if [ ! -d "$dir" ]; then
        log_fatal "$message"
    fi
}

# Graceful degradation - try command, continue on failure
# Usage: error_try "description" command args...
error_try() {
    local description="$1"
    shift

    if "$@"; then
        log_debug "Success: $description"
        return 0
    else
        local exit_code=$?
        log_warn "Failed (continuing): $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Create temporary file with cleanup
# Usage: tmpfile=$(error_temp_file "prefix")
error_temp_file() {
    local prefix="${1:-wrtbwmon}"
    local tmpfile=$(mktemp "/tmp/${prefix}.XXXXXX")

    # Register cleanup
    error_register_cleanup "rm -f '$tmpfile'"

    echo "$tmpfile"
}

# Create temporary directory with cleanup
# Usage: tmpdir=$(error_temp_dir "prefix")
error_temp_dir() {
    local prefix="${1:-wrtbwmon}"
    local tmpdir=$(mktemp -d "/tmp/${prefix}.XXXXXX")

    # Register cleanup
    error_register_cleanup "rm -rf '$tmpdir'"

    echo "$tmpdir"
}

# Test function
_error_test() {
    echo "=== Error Handler Test ==="

    # Enable logging to stdout
    LOG_TO_STDOUT=1
    log_set_level "debug"

    echo ""
    echo "Test 1: Cleanup handlers"
    cleanup_test() {
        echo "  Cleanup function called!"
    }
    error_register_cleanup "cleanup_test"

    echo ""
    echo "Test 2: Error context"
    error_set_context "Processing test data"
    log_error "This error has context"
    error_clear_context

    echo ""
    echo "Test 3: Error messages"
    for code in 0 1 2 3 4 5; do
        echo "  Code $code: $(error_get_message $code)"
    done

    echo ""
    echo "Test 4: Command requirements"
    error_require_command "sh" "Shell not found"
    echo "  ✓ Shell found"

    echo ""
    echo "Test 5: Retry mechanism"
    _test_counter=0
    _test_fail_twice() {
        _test_counter=$((_test_counter + 1))
        if [ $_test_counter -lt 3 ]; then
            echo "  Attempt $_test_counter: failing..."
            return 1
        fi
        echo "  Attempt $_test_counter: success!"
        return 0
    }
    error_retry 5 "test command" _test_fail_twice

    echo ""
    echo "Test 6: Temporary file with cleanup"
    tmpfile=$(error_temp_file "test")
    echo "  Created temp file: $tmpfile"
    echo "test data" > "$tmpfile"

    echo ""
    echo "=== Test Complete ==="
    echo "Note: Cleanup will run on exit"
}

# Run test if executed directly
if [ "${0##*/}" = "error_handler.sh" ]; then
    case "${1:-}" in
        test)
            _error_test
            ;;
        *)
            echo "Usage: $0 test"
            echo ""
            echo "Or source this file in your script:"
            echo "  . /usr/lib/wrtbwmon/error_handler.sh"
            echo "  error_enable_trap"
            echo ""
            echo "Available functions:"
            echo "  error_enable_trap       - Enable error trapping"
            echo "  error_register_cleanup  - Register cleanup function"
            echo "  error_set_context       - Set error context"
            echo "  error_exec              - Execute with error handling"
            echo "  error_retry             - Retry on failure"
            echo "  error_check             - Check exit code"
            echo "  error_require_command   - Require command exists"
            echo "  error_require_file      - Require file exists"
            echo "  error_temp_file         - Create temp file with cleanup"
            ;;
    esac
fi
