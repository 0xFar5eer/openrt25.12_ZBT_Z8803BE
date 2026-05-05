#!/bin/sh
# Retry Logic Library for wrtbwmon
# Provides reusable retry mechanisms with exponential backoff

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

# Simple retry with fixed delay
# Usage: retry_fixed <max_attempts> <delay_seconds> <command> [args...]
# Returns: Command exit code (0 on success, last error code on failure)
retry_fixed() {
    local max_attempts=$1
    local delay=$2
    shift 2

    local attempt=1
    local exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $*"

        if "$@"; then
            log_debug "Success on attempt $attempt"
            return 0
        fi

        exit_code=$?

        if [ $attempt -lt $max_attempts ]; then
            log_debug "Attempt $attempt failed (exit code: $exit_code), retrying in ${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
        else
            log_warn "All $max_attempts attempts failed (exit code: $exit_code)"
            return $exit_code
        fi
    done

    return $exit_code
}

# Retry with exponential backoff
# Usage: retry_backoff <max_attempts> <initial_delay> <max_delay> <command> [args...]
# Returns: Command exit code (0 on success, last error code on failure)
retry_backoff() {
    local max_attempts=$1
    local initial_delay=$2
    local max_delay=$3
    shift 3

    local attempt=1
    local delay=$initial_delay
    local exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts (delay: ${delay}s): $*"

        if "$@"; then
            log_debug "Success on attempt $attempt"
            return 0
        fi

        exit_code=$?

        if [ $attempt -lt $max_attempts ]; then
            log_debug "Attempt $attempt failed (exit code: $exit_code), retrying in ${delay}s..."
            sleep $delay

            # Exponential backoff: double the delay, cap at max_delay
            delay=$((delay * 2))
            if [ $delay -gt $max_delay ]; then
                delay=$max_delay
            fi

            attempt=$((attempt + 1))
        else
            log_warn "All $max_attempts attempts failed (exit code: $exit_code)"
            return $exit_code
        fi
    done

    return $exit_code
}

# Retry with jitter (randomized delay to avoid thundering herd)
# Usage: retry_jitter <max_attempts> <base_delay> <max_delay> <command> [args...]
# Returns: Command exit code (0 on success, last error code on failure)
retry_jitter() {
    local max_attempts=$1
    local base_delay=$2
    local max_delay=$3
    shift 3

    local attempt=1
    local exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $*"

        if "$@"; then
            log_debug "Success on attempt $attempt"
            return 0
        fi

        exit_code=$?

        if [ $attempt -lt $max_attempts ]; then
            # Calculate delay with jitter: base_delay * 2^attempt + random(0, base_delay)
            local exponential=$((base_delay * (1 << (attempt - 1))))
            local jitter=$((RANDOM % (base_delay + 1)))
            local delay=$((exponential + jitter))

            # Cap at max_delay
            if [ $delay -gt $max_delay ]; then
                delay=$max_delay
            fi

            log_debug "Attempt $attempt failed (exit code: $exit_code), retrying in ${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
        else
            log_warn "All $max_attempts attempts failed (exit code: $exit_code)"
            return $exit_code
        fi
    done

    return $exit_code
}

# Retry until success (infinite retry with delay)
# Usage: retry_until_success <delay_seconds> <command> [args...]
# Returns: Never returns (runs until success or killed)
retry_until_success() {
    local delay=$1
    shift

    local attempt=1

    while true; do
        log_debug "Attempt $attempt: $*"

        if "$@"; then
            log_info "Success on attempt $attempt"
            return 0
        fi

        local exit_code=$?
        log_warn "Attempt $attempt failed (exit code: $exit_code), retrying in ${delay}s..."
        sleep $delay
        attempt=$((attempt + 1))
    done
}

# Retry with timeout
# Usage: retry_timeout <timeout_seconds> <retry_delay> <command> [args...]
# Returns: Command exit code (0 on success, 124 on timeout)
retry_timeout() {
    local timeout=$1
    local retry_delay=$2
    shift 2

    local start_time=$(date +%s)
    local attempt=1

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout after ${elapsed}s (${attempt} attempts)"
            return 124  # Standard timeout exit code
        fi

        log_debug "Attempt $attempt (elapsed: ${elapsed}s/${timeout}s): $*"

        if "$@"; then
            log_debug "Success on attempt $attempt (elapsed: ${elapsed}s)"
            return 0
        fi

        local exit_code=$?
        log_debug "Attempt $attempt failed (exit code: $exit_code), retrying in ${retry_delay}s..."
        sleep $retry_delay
        attempt=$((attempt + 1))
    done
}

# Retry only on specific exit codes
# Usage: retry_on_codes <max_attempts> <delay> <exit_codes> <command> [args...]
# Example: retry_on_codes 5 1 "5,11" sqlite3 "$DB" ".tables"  # Retry on BUSY(5) and LOCKED(11)
# Returns: Command exit code
retry_on_codes() {
    local max_attempts=$1
    local delay=$2
    local retry_codes="$3"
    shift 3

    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $*"

        "$@"
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log_debug "Success on attempt $attempt"
            return 0
        fi

        # Check if exit code is in retry list
        local should_retry=0
        local IFS=','
        for code in $retry_codes; do
            if [ "$exit_code" = "$code" ]; then
                should_retry=1
                break
            fi
        done

        if [ $should_retry -eq 1 ] && [ $attempt -lt $max_attempts ]; then
            log_debug "Attempt $attempt failed with retryable code $exit_code, retrying in ${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
        else
            if [ $should_retry -eq 0 ]; then
                log_warn "Attempt $attempt failed with non-retryable code $exit_code, aborting"
            else
                log_warn "All $max_attempts attempts failed (exit code: $exit_code)"
            fi
            return $exit_code
        fi
    done

    return $exit_code
}

# Retry with custom condition check
# Usage: retry_while <max_attempts> <delay> <condition_func> <command> [args...]
# The condition_func should return 0 to continue retrying, non-zero to stop
# Returns: Command exit code
retry_while() {
    local max_attempts=$1
    local delay=$2
    local condition_func=$3
    shift 3

    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $*"

        "$@"
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log_debug "Success on attempt $attempt"
            return 0
        fi

        # Check custom condition
        if $condition_func $exit_code && [ $attempt -lt $max_attempts ]; then
            log_debug "Attempt $attempt failed (exit code: $exit_code), condition allows retry in ${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
        else
            log_warn "Retry condition not met or max attempts reached (exit code: $exit_code)"
            return $exit_code
        fi
    done

    return $exit_code
}

# Database-specific retry (handles SQLite BUSY and LOCKED errors)
# Usage: retry_db <max_attempts> <command> [args...]
# Returns: Command exit code
retry_db() {
    local max_attempts=$1
    shift

    # SQLite error codes: 5=BUSY, 6=LOCKED
    retry_on_codes $max_attempts 1 "5,6" "$@"
}

# Network-specific retry (handles common network errors)
# Usage: retry_network <max_attempts> <command> [args...]
# Returns: Command exit code
retry_network() {
    local max_attempts=$1
    shift

    # Common network error codes: 7=connection refused, 28=timeout, 56=network error
    retry_backoff $max_attempts 1 10 "$@"
}

# Test function
_retry_test() {
    echo "=== Retry Library Test ==="

    # Enable logging
    LOG_TO_STDOUT=1
    log_set_level "debug"

    echo ""
    echo "Test 1: Fixed retry (should succeed on attempt 3)"
    _test_counter=0
    _test_fail_twice() {
        _test_counter=$((_test_counter + 1))
        if [ $_test_counter -lt 3 ]; then
            echo "  Failing (attempt $_test_counter)"
            return 1
        fi
        echo "  Success (attempt $_test_counter)"
        return 0
    }
    retry_fixed 5 1 _test_fail_twice

    echo ""
    echo "Test 2: Exponential backoff"
    _test_counter=0
    retry_backoff 3 1 8 _test_fail_twice

    echo ""
    echo "Test 3: Retry on specific codes"
    _test_with_code() {
        echo "  Returning code 5 (BUSY)"
        return 5
    }
    retry_on_codes 3 1 "5,6" _test_with_code || echo "  Failed as expected"

    echo ""
    echo "Test 4: Database retry"
    _test_db_busy() {
        echo "  Simulating database BUSY"
        return 5
    }
    retry_db 3 _test_db_busy || echo "  Failed as expected"

    echo ""
    echo "=== Test Complete ==="
}

# Run test if executed directly
if [ "${0##*/}" = "retry.sh" ]; then
    case "${1:-}" in
        test)
            _retry_test
            ;;
        *)
            echo "Usage: $0 test"
            echo ""
            echo "Or source this file in your script:"
            echo "  . /usr/lib/wrtbwmon/retry.sh"
            echo ""
            echo "Available functions:"
            echo "  retry_fixed         - Fixed delay retry"
            echo "  retry_backoff       - Exponential backoff"
            echo "  retry_jitter        - Jittered backoff"
            echo "  retry_until_success - Infinite retry"
            echo "  retry_timeout       - Retry with timeout"
            echo "  retry_on_codes      - Retry on specific exit codes"
            echo "  retry_while         - Retry with custom condition"
            echo "  retry_db            - Database-specific retry"
            echo "  retry_network       - Network-specific retry"
            ;;
    esac
fi
