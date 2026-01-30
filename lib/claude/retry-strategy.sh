#!/usr/bin/env bash
# retry-strategy.sh - Exponential backoff retry logic for Claude invocations
#
# Provides retry wrapper for transient Claude service errors (exit code 5)
# and HTTP 429 rate-limit errors (which may surface as exit code 1).
# Uses exponential backoff with configurable limits.
set -euo pipefail

[ -n "${_RETRY_STRATEGY_LOADED:-}" ] && return 0
_RETRY_STRATEGY_LOADED=1

source "$WIGGUM_HOME/lib/core/logger.sh"
source "$WIGGUM_HOME/lib/core/defaults.sh"

# =============================================================================
# RETRY CONFIGURATION
# =============================================================================

# Default retry configuration (can be overridden by config.json or env vars)
CLAUDE_MAX_RETRIES="${WIGGUM_CLAUDE_MAX_RETRIES:-3}"
CLAUDE_INITIAL_BACKOFF="${WIGGUM_CLAUDE_INITIAL_BACKOFF:-5}"      # seconds
CLAUDE_MAX_BACKOFF="${WIGGUM_CLAUDE_MAX_BACKOFF:-60}"             # seconds
CLAUDE_BACKOFF_MULTIPLIER="${WIGGUM_CLAUDE_BACKOFF_MULTIPLIER:-2}"

# Exit codes considered retryable
# 5 = Claude CLI error (API/service issues)
# 124 = timeout (command timed out)
_RETRYABLE_EXIT_CODES=(5 124)

# Stderr patterns indicating an HTTP 429 / rate-limit error
# (Claude CLI sometimes exits 1 instead of 5 for these)
_RATE_LIMIT_PATTERNS=("429" "rate limit" "too many requests" "High concurrency")

# =============================================================================
# RETRY HELPER FUNCTIONS
# =============================================================================

# Load retry config from config.json (with env var overrides)
load_claude_retry_config() {
    local config_file="$WIGGUM_HOME/config/config.json"
    if [ -f "$config_file" ]; then
        CLAUDE_MAX_RETRIES="${WIGGUM_CLAUDE_MAX_RETRIES:-$(jq -r '.claude.max_retries // 3' "$config_file" 2>/dev/null)}"
        CLAUDE_INITIAL_BACKOFF="${WIGGUM_CLAUDE_INITIAL_BACKOFF:-$(jq -r '.claude.initial_backoff_seconds // 5' "$config_file" 2>/dev/null)}"
        CLAUDE_MAX_BACKOFF="${WIGGUM_CLAUDE_MAX_BACKOFF:-$(jq -r '.claude.max_backoff_seconds // 60' "$config_file" 2>/dev/null)}"
        CLAUDE_BACKOFF_MULTIPLIER="${WIGGUM_CLAUDE_BACKOFF_MULTIPLIER:-$(jq -r '.claude.backoff_multiplier // 2' "$config_file" 2>/dev/null)}"
    fi
    # Ensure defaults if parsing fails
    CLAUDE_MAX_RETRIES="${CLAUDE_MAX_RETRIES:-3}"
    CLAUDE_INITIAL_BACKOFF="${CLAUDE_INITIAL_BACKOFF:-5}"
    CLAUDE_MAX_BACKOFF="${CLAUDE_MAX_BACKOFF:-60}"
    CLAUDE_BACKOFF_MULTIPLIER="${CLAUDE_BACKOFF_MULTIPLIER:-2}"
}

# Check if an exit code is retryable
#
# Args:
#   exit_code - The exit code to check
#
# Returns: 0 if retryable, 1 if not
_is_retryable_exit_code() {
    local exit_code="$1"
    local code
    for code in "${_RETRYABLE_EXIT_CODES[@]}"; do
        if [ "$exit_code" -eq "$code" ]; then
            return 0
        fi
    done
    return 1
}

# Check if a stderr capture file contains rate-limit error indicators
#
# Args:
#   stderr_file - Path to file containing captured stderr output
#
# Returns: 0 if rate-limit error detected, 1 if not
_is_rate_limit_error() {
    local stderr_file="$1"
    [ -s "$stderr_file" ] || return 1

    local pattern
    for pattern in "${_RATE_LIMIT_PATTERNS[@]}"; do
        if grep -qi "$pattern" "$stderr_file" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Calculate backoff delay for a given attempt number
#
# Args:
#   attempt - The attempt number (0-indexed)
#
# Returns: Delay in seconds (echoed)
_calculate_backoff() {
    local attempt="$1"
    local delay="$CLAUDE_INITIAL_BACKOFF"

    # Exponential backoff: initial * multiplier^attempt
    local i=0
    while [ "$i" -lt "$attempt" ]; do
        delay=$((delay * CLAUDE_BACKOFF_MULTIPLIER))
        ((++i))
    done

    # Cap at max backoff
    if [ "$delay" -gt "$CLAUDE_MAX_BACKOFF" ]; then
        delay="$CLAUDE_MAX_BACKOFF"
    fi

    echo "$delay"
}

# =============================================================================
# RETRY WRAPPER FUNCTION
# =============================================================================

# Run Claude with retry logic for transient failures
#
# Wraps run_claude (from defaults.sh) with exponential backoff retry.
# Only retries on specific exit codes (5=Claude error, 124=timeout).
#
# Args:
#   All arguments are passed through to run_claude
#
# Returns: Exit code from final attempt
run_claude_with_retry() {
    # Load config on first use
    load_claude_retry_config

    local attempt=0
    local exit_code=0

    # Temp file for capturing stderr to detect rate-limit errors
    local _retry_stderr_file
    _retry_stderr_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$_retry_stderr_file'" RETURN

    while [ "$attempt" -le "$CLAUDE_MAX_RETRIES" ]; do
        # Clear stderr capture between attempts
        : > "$_retry_stderr_file"

        # Run claude, capturing stderr for rate-limit detection
        exit_code=0
        run_claude "$@" 2>"$_retry_stderr_file" || exit_code=$?

        # Replay captured stderr to the caller
        if [ -s "$_retry_stderr_file" ]; then
            cat "$_retry_stderr_file" >&2
        fi

        # Success - return immediately
        if [ "$exit_code" -eq 0 ]; then
            return 0
        fi

        # Check if retryable by exit code
        local retryable=false
        if _is_retryable_exit_code "$exit_code"; then
            retryable=true
        elif [ "$exit_code" -eq 1 ] && _is_rate_limit_error "$_retry_stderr_file"; then
            log_warn "Detected rate-limit error in stderr (exit code 1) - treating as retryable"
            retryable=true
        fi

        if [ "$retryable" != true ]; then
            log_debug "Claude failed with non-retryable exit code $exit_code"
            return "$exit_code"
        fi

        # Check if we've exhausted retries
        if [ "$attempt" -ge "$CLAUDE_MAX_RETRIES" ]; then
            log_warn "Claude failed (exit $exit_code) after $((attempt + 1)) attempts - giving up"
            return "$exit_code"
        fi

        # Calculate backoff delay
        local delay
        delay=$(_calculate_backoff "$attempt")

        log_warn "Claude failed (exit $exit_code), retrying in ${delay}s (attempt $((attempt + 1))/$CLAUDE_MAX_RETRIES)"
        sleep "$delay"

        ((++attempt)) || true
    done

    return "$exit_code"
}

# =============================================================================
# CONVENIENCE ALIASES
# =============================================================================

# Alias for explicit retry behavior
retry_claude() {
    run_claude_with_retry "$@"
}
