#!/usr/bin/env bash
# Logging utilities for Chief Wiggum
#
# Log Levels (in order of severity):
#   DEBUG - Detailed diagnostic information (only when DEBUG=1 or LOG_LEVEL=DEBUG)
#   INFO  - General operational messages (default level)
#   WARN  - Warning conditions that should be reviewed
#   ERROR - Error conditions requiring attention
#
# Environment variables:
#   LOG_FILE  - Optional file to append all logs to (in addition to stdout/stderr)
#   LOG_LEVEL - Minimum level to output: DEBUG, INFO, WARN, ERROR (default: INFO)
#   DEBUG     - If set to 1, equivalent to LOG_LEVEL=DEBUG (legacy compatibility)
set -euo pipefail

# Log level numeric values for comparison
_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;  # default to INFO
    esac
}

# Check if a log level should be output
_should_log() {
    local level="$1"
    local min_level="${LOG_LEVEL:-INFO}"

    # DEBUG=1 overrides LOG_LEVEL for backwards compatibility
    if [[ "${DEBUG:-0}" == "1" ]]; then
        min_level="DEBUG"
    fi

    local level_val min_val
    level_val=$(_log_level_value "$level")
    min_val=$(_log_level_value "$min_level")

    [[ $level_val -ge $min_val ]]
}

# Internal: format and output a log message
_log_output() {
    local level="$1"
    local message="$2"
    local stream="${3:-1}"  # 1=stdout, 2=stderr

    # Check if we should log at this level
    if ! _should_log "$level"; then
        return
    fi

    local formatted
    formatted="[$(date -Iseconds)] ${level}: $message"

    # Output to appropriate stream
    if [[ "$stream" == "2" ]]; then
        echo "$formatted" >&2
    else
        echo "$formatted"
    fi

    # Append to LOG_FILE if set
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

# Log at INFO level (to stdout)
log() {
    _log_output "INFO" "$1" 1
}

# Alias for log() with explicit name
log_info() {
    _log_output "INFO" "$1" 1
}

# Log at WARN level (to stderr)
log_warn() {
    _log_output "WARN" "$1" 2
}

# Log at ERROR level (to stderr)
log_error() {
    _log_output "ERROR" "$1" 2
}

# Log at DEBUG level (to stderr, only when DEBUG=1 or LOG_LEVEL=DEBUG)
log_debug() {
    _log_output "DEBUG" "$1" 2
}

# Capture command output with logging
# Usage: log_command "description" command args...
# Output goes to stdout and LOG_FILE (if set)
log_command() {
    local description="$1"
    shift
    log_debug "Executing: $description"
    if [[ -n "${LOG_FILE:-}" ]]; then
        "$@" 2>&1 | while IFS= read -r line; do
            echo "[$(date -Iseconds)] OUTPUT: $line" | tee -a "$LOG_FILE"
        done
    else
        "$@" 2>&1
    fi
}

# =============================================================================
# SECTION DIVIDERS AND HEADERS
# =============================================================================

# Log a major section divider (double line)
# Usage: log_section "Section Name"
log_section() {
    local title="$1"
    local width=70
    local line
    line=$(printf '=%.0s' $(seq 1 $width))

    _log_output "INFO" "" 1
    _log_output "INFO" "$line" 1
    _log_output "INFO" "  $title" 1
    _log_output "INFO" "$line" 1
}

# Log a minor section divider (single line)
# Usage: log_subsection "Subsection Name"
log_subsection() {
    local title="$1"
    local width=70
    local line
    line=$(printf -- '-%.0s' $(seq 1 $width))

    _log_output "INFO" "" 1
    _log_output "INFO" "$line" 1
    _log_output "INFO" "  $title" 1
    _log_output "INFO" "$line" 1
}

# Log a key-value pair (for config display)
# Usage: log_kv "key" "value"
log_kv() {
    local key="$1"
    local value="$2"
    local padding=25

    printf -v formatted "  %-${padding}s : %s" "$key" "$value"
    _log_output "INFO" "$formatted" 1
}

# Log agent header with full context
# Usage: log_agent_header "agent_type" "worker_id" "task_id"
log_agent_header() {
    local agent_type="$1"
    local worker_id="${2:-}"
    local task_id="${3:-}"
    local step_id="${WIGGUM_STEP_ID:-}"

    log_section "AGENT: $agent_type"
    [ -n "$step_id" ] && log_kv "Step ID" "$step_id"
    [ -n "$worker_id" ] && log_kv "Worker ID" "$worker_id"
    [ -n "$task_id" ] && log_kv "Task ID" "$task_id"
    log_kv "Started" "$(date -Iseconds)"
}

# Log agent completion with status
# Usage: log_agent_complete "agent_type" "exit_code" "duration_secs"
log_agent_complete() {
    local agent_type="$1"
    local exit_code="${2:-0}"
    local duration="${3:-}"
    local status="SUCCESS"

    [ "$exit_code" -ne 0 ] && status="FAILED (exit=$exit_code)"

    log_subsection "COMPLETED: $agent_type"
    log_kv "Status" "$status"
    [ -n "$duration" ] && log_kv "Duration" "${duration}s"
    log_kv "Finished" "$(date -Iseconds)"
    _log_output "INFO" "" 1
}

# Log configuration block
# Usage: log_config_block "Config Name" <<< "key1=val1\nkey2=val2"
# Or: log_config_block "Config Name" "key1" "val1" "key2" "val2"
log_config_block() {
    local title="$1"
    shift

    log_subsection "CONFIG: $title"

    if [ $# -eq 0 ]; then
        # Read from stdin
        while IFS='=' read -r key value; do
            [ -n "$key" ] && log_kv "$key" "$value"
        done
    else
        # Read from args (key value pairs)
        while [ $# -ge 2 ]; do
            log_kv "$1" "$2"
            shift 2
        done
    fi
}
