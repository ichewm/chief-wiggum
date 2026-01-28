#!/usr/bin/env bash
# defaults.sh - Centralized configuration defaults and path setup
#
# Source this file early in any wiggum script to get consistent defaults.
# All values can be overridden by environment variables.
set -euo pipefail

# Core paths
WIGGUM_HOME="${WIGGUM_HOME:-$HOME/.claude/chief-wiggum}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
RALPH_DIR="${RALPH_DIR:-$PROJECT_DIR/.ralph}"

# Claude binary (allows specifying a different binary or path)
CLAUDE="${CLAUDE:-claude}"

# Pass through API configuration environment variables if set
# These allow custom API endpoints, authentication, and model selection
# Use ${VAR:-} syntax to handle set -u (nounset) mode
[ -n "${ANTHROPIC_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL
[ -n "${API_TIMEOUT_MS:-}" ] && export API_TIMEOUT_MS
[ -n "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" ] && export ANTHROPIC_DEFAULT_OPUS_MODEL
[ -n "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ] && export ANTHROPIC_DEFAULT_SONNET_MODEL
[ -n "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" ] && export ANTHROPIC_DEFAULT_HAIKU_MODEL

# Security: Store auth token in non-exported variable to limit exposure
# Use run_claude() helper to pass token only to Claude CLI
_WIGGUM_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"

# Helper to run Claude CLI with auth token scoped only to that process
# Usage: run_claude [claude args...]
# This prevents the token from being exposed to all child processes
run_claude() {
    if [ -n "$_WIGGUM_AUTH_TOKEN" ]; then
        ANTHROPIC_AUTH_TOKEN="$_WIGGUM_AUTH_TOKEN" "$CLAUDE" "$@"
    else
        "$CLAUDE" "$@"
    fi
}

# Logging configuration
# Map WIGGUM_LOG_LEVEL to LOG_LEVEL for logger.sh
if [ -n "${WIGGUM_LOG_LEVEL:-}" ]; then
    LOG_LEVEL="${WIGGUM_LOG_LEVEL^^}"  # Convert to uppercase
    export LOG_LEVEL
fi

# Worker configuration defaults
MAX_WORKERS="${WIGGUM_MAX_WORKERS:-4}"
export MAX_WORKERS

# Resolve worker timeout (seconds) - max runtime for conflict resolver workers
RESOLVE_WORKER_TIMEOUT="${WIGGUM_RESOLVE_TIMEOUT:-1800}"
export RESOLVE_WORKER_TIMEOUT

# Maximum merge attempts before giving up
MAX_MERGE_ATTEMPTS="${WIGGUM_MAX_MERGE_ATTEMPTS:-3}"
export MAX_MERGE_ATTEMPTS

# GitHub CLI timeout (seconds)
WIGGUM_GH_TIMEOUT="${WIGGUM_GH_TIMEOUT:-30}"
export WIGGUM_GH_TIMEOUT

# Error log max age for status display (seconds) - only show errors newer than this
ERROR_LOG_MAX_AGE="${WIGGUM_ERROR_LOG_MAX_AGE:-3600}"
export ERROR_LOG_MAX_AGE

# Stuck worker detection: warn if no activity for this many seconds (0 = disabled)
STUCK_WORKER_THRESHOLD="${WIGGUM_STUCK_WORKER_THRESHOLD:-1800}"
export STUCK_WORKER_THRESHOLD

# Export for child processes
export WIGGUM_HOME
export PROJECT_DIR
export RALPH_DIR
export CLAUDE

# Load review config from config.json (with env var overrides)
load_review_config() {
    local config_file="$WIGGUM_HOME/config/config.json"
    if [ -f "$config_file" ]; then
        WIGGUM_APPROVED_AUTHORS="${WIGGUM_APPROVED_AUTHORS:-$(jq -r '.review.approved_authors // [] | join(",")' "$config_file" 2>/dev/null)}"
        WIGGUM_COMMENT_FIX_MAX_ITERATIONS="${WIGGUM_COMMENT_FIX_MAX_ITERATIONS:-$(jq -r '.review.fix_max_iterations // 10' "$config_file" 2>/dev/null)}"
        WIGGUM_COMMENT_FIX_MAX_TURNS="${WIGGUM_COMMENT_FIX_MAX_TURNS:-$(jq -r '.review.fix_max_turns // 30' "$config_file" 2>/dev/null)}"
        WIGGUM_AUTO_COMMIT_AFTER_FIX="${WIGGUM_AUTO_COMMIT_AFTER_FIX:-$(jq -r '.review.auto_commit_after_fix // true' "$config_file" 2>/dev/null)}"
    fi
    # Fallback defaults if config doesn't exist or parsing fails
    WIGGUM_APPROVED_AUTHORS="${WIGGUM_APPROVED_AUTHORS:-copilot,dependabot,github-actions[bot],dependabot[bot],renovate[bot],codecov[bot]}"
    WIGGUM_COMMENT_FIX_MAX_ITERATIONS="${WIGGUM_COMMENT_FIX_MAX_ITERATIONS:-10}"
    WIGGUM_COMMENT_FIX_MAX_TURNS="${WIGGUM_COMMENT_FIX_MAX_TURNS:-30}"
    WIGGUM_AUTO_COMMIT_AFTER_FIX="${WIGGUM_AUTO_COMMIT_AFTER_FIX:-true}"

    export WIGGUM_APPROVED_AUTHORS
    export WIGGUM_COMMENT_FIX_MAX_ITERATIONS
    export WIGGUM_COMMENT_FIX_MAX_TURNS
    export WIGGUM_AUTO_COMMIT_AFTER_FIX
}

# Load rate limit config from config.json (with env var overrides)
load_rate_limit_config() {
    local config_file="$WIGGUM_HOME/config/config.json"
    if [ -f "$config_file" ]; then
        WIGGUM_RATE_LIMIT_THRESHOLD="${WIGGUM_RATE_LIMIT_THRESHOLD:-$(jq -r '.rate_limit.threshold_prompts // 900' "$config_file" 2>/dev/null)}"
    fi
    WIGGUM_RATE_LIMIT_THRESHOLD="${WIGGUM_RATE_LIMIT_THRESHOLD:-900}"
    export WIGGUM_RATE_LIMIT_THRESHOLD
}

# Load git identity config from config.json (with env var overrides)
# Sets WIGGUM_GIT_AUTHOR_NAME and WIGGUM_GIT_AUTHOR_EMAIL
load_git_config() {
    local config_file="$WIGGUM_HOME/config/config.json"
    if [ -f "$config_file" ]; then
        WIGGUM_GIT_AUTHOR_NAME="${WIGGUM_GIT_AUTHOR_NAME:-$(jq -r '.git.author_name // "Ralph Wiggum"' "$config_file" 2>/dev/null)}"
        WIGGUM_GIT_AUTHOR_EMAIL="${WIGGUM_GIT_AUTHOR_EMAIL:-$(jq -r '.git.author_email // "ralph@wiggum.cc"' "$config_file" 2>/dev/null)}"
    fi
    # Fallback defaults if config doesn't exist or parsing fails
    WIGGUM_GIT_AUTHOR_NAME="${WIGGUM_GIT_AUTHOR_NAME:-Ralph Wiggum}"
    WIGGUM_GIT_AUTHOR_EMAIL="${WIGGUM_GIT_AUTHOR_EMAIL:-ralph@wiggum.cc}"
    export WIGGUM_GIT_AUTHOR_NAME
    export WIGGUM_GIT_AUTHOR_EMAIL
}
