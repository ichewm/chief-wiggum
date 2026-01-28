#!/usr/bin/env bash
# Run Claude agent once with configurable parameters
# Generic one-shot agent execution
set -euo pipefail

source "$WIGGUM_HOME/lib/core/logger.sh"
source "$WIGGUM_HOME/lib/core/defaults.sh"
source "$WIGGUM_HOME/lib/claude/retry-strategy.sh"

run_agent_once() {
    local workspace="$1"
    local system_prompt="$2"
    local user_prompt="$3"
    local output_file="$4"
    local max_turns="${5:-3}"
    local session_id="${6:-}"
    _run_once_completed_normally=false

    # Exit handler for detecting unexpected exits
    # shellcheck disable=SC2329
    _run_once_exit_handler() {
        local exit_code=$?
        if [ "$_run_once_completed_normally" != true ]; then
            log_error "Unexpected exit from run_agent_once (exit_code=$exit_code, workspace=$workspace)"
        fi
        trap - EXIT
    }
    trap _run_once_exit_handler EXIT

    # Validate required parameters
    if [ -z "$workspace" ] || [ -z "$system_prompt" ] || [ -z "$user_prompt" ]; then
        log_error "run_agent_once: missing required parameters"
        log_error "Usage: run_agent_once <workspace> <system_prompt> <user_prompt> [output_file] [max_turns] [session_id]"
        return 1
    fi

    # Change to workspace
    cd "$workspace" || {
        log_error "run_agent_once: failed to cd to workspace: $workspace"
        return 1
    }

    log_debug "Running agent once in workspace: $workspace (max_turns: $max_turns)"

    # Build command arguments
    local cmd_args=(
        --verbose
        --output-format stream-json
        --append-system-prompt "$system_prompt"
        --max-turns "$max_turns"
        --dangerously-skip-permissions
        -p "$user_prompt"
    )

    # Add plugin dir if WIGGUM_HOME is set
    if [ -n "$WIGGUM_HOME" ]; then
        cmd_args+=(--plugin-dir "$WIGGUM_HOME/skills")
    fi

    # Add session-id or resume based on whether we're continuing
    if [ -n "$session_id" ]; then
        cmd_args+=(--resume "$session_id")
    fi

    # Auto-generate log file path if not specified
    if [ -z "$output_file" ] && [ -n "${WIGGUM_LOG_DIR:-}" ]; then
        mkdir -p "$WIGGUM_LOG_DIR"
        output_file="$WIGGUM_LOG_DIR/once-$(date +%s)-$$.log"
        log_debug "Auto-generated log file: $output_file"
    fi

    # Run claude with retry and capture output
    if [ -n "$output_file" ]; then
        local exit_code=0
        run_claude_with_retry "${cmd_args[@]}" > "$output_file" 2>&1 || exit_code=$?
        log_debug "Agent completed (exit_code: $exit_code, output: $output_file)"
        _run_once_completed_normally=true
        return $exit_code
    else
        # No WIGGUM_LOG_DIR set - output goes to stdout only (not recommended)
        local exit_code=0
        run_claude_with_retry "${cmd_args[@]}" 2>&1 || exit_code=$?
        _run_once_completed_normally=true
        return $exit_code
    fi
}

# Run agent once with a specific session ID (creates a named session)
#
# Unlike run_agent_once which uses --resume for existing sessions,
# this function uses --session-id to CREATE a new session with a specific UUID.
# Used by live mode for the initial session creation.
#
# Args:
#   workspace      - Directory to run claude in
#   system_prompt  - System prompt for context
#   user_prompt    - User prompt (the task)
#   output_file    - Where to save output
#   max_turns      - Max turns (default: 3)
#   session_id     - UUID for the new session
#
# Returns: Exit code from claude
run_agent_once_with_session() {
    local workspace="$1"
    local system_prompt="$2"
    local user_prompt="$3"
    local output_file="$4"
    local max_turns="${5:-3}"
    local session_id="$6"
    _run_once_with_session_completed_normally=false

    # Exit handler for detecting unexpected exits
    # shellcheck disable=SC2329
    _run_once_with_session_exit_handler() {
        local exit_code=$?
        if [ "$_run_once_with_session_completed_normally" != true ]; then
            log_error "Unexpected exit from run_agent_once_with_session (exit_code=$exit_code, workspace=$workspace)"
        fi
        trap - EXIT
    }
    trap _run_once_with_session_exit_handler EXIT

    # Validate required parameters
    if [ -z "$workspace" ] || [ -z "$system_prompt" ] || [ -z "$user_prompt" ] || [ -z "$session_id" ]; then
        log_error "run_agent_once_with_session: missing required parameters"
        log_error "Usage: run_agent_once_with_session <workspace> <system_prompt> <user_prompt> <output_file> <max_turns> <session_id>"
        return 1
    fi

    # Change to workspace
    cd "$workspace" || {
        log_error "run_agent_once_with_session: failed to cd to workspace: $workspace"
        return 1
    }

    log_debug "Running agent with named session in workspace: $workspace (max_turns: $max_turns, session_id: $session_id)"

    # Build command arguments - use --session-id to CREATE new named session
    local cmd_args=(
        --verbose
        --output-format stream-json
        --append-system-prompt "$system_prompt"
        --max-turns "$max_turns"
        --session-id "$session_id"
        --dangerously-skip-permissions
        -p "$user_prompt"
    )

    # Add plugin dir if WIGGUM_HOME is set
    if [ -n "$WIGGUM_HOME" ]; then
        cmd_args+=(--plugin-dir "$WIGGUM_HOME/skills")
    fi

    # Auto-generate log file path if not specified
    if [ -z "$output_file" ] && [ -n "${WIGGUM_LOG_DIR:-}" ]; then
        mkdir -p "$WIGGUM_LOG_DIR"
        output_file="$WIGGUM_LOG_DIR/once-session-$(date +%s)-$$.log"
        log_debug "Auto-generated log file: $output_file"
    fi

    # Run claude with retry and capture output
    if [ -n "$output_file" ]; then
        local exit_code=0
        run_claude_with_retry "${cmd_args[@]}" > "$output_file" 2>&1 || exit_code=$?
        log_debug "Agent completed with session (exit_code: $exit_code, output: $output_file)"
        _run_once_with_session_completed_normally=true
        return $exit_code
    else
        # No output file - output goes to stdout only (not recommended)
        local exit_code=0
        run_claude_with_retry "${cmd_args[@]}" 2>&1 || exit_code=$?
        _run_once_with_session_completed_normally=true
        return $exit_code
    fi
}
