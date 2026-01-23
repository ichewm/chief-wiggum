#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# AGENT METADATA
# =============================================================================
# AGENT_TYPE: resume-decide
# AGENT_DESCRIPTION: Analyzes previous worker conversation logs and worker.log
#   to decide which step to resume from (or ABORT). Produces resume instructions
#   for the resumed worker with context about what was accomplished and what
#   needs to happen next.
# REQUIRED_PATHS:
#   - conversations : Directory with converted conversation markdown files
#   - worker.log    : Phase-level status log from previous run
# OUTPUT_FILES:
#   - resume-step.txt         : Contains the step name to resume from (or ABORT)
#   - resume-instructions.md  : Context and guidance for the resumed worker
# =============================================================================

# Source base library and initialize metadata
source "$WIGGUM_HOME/lib/core/agent-base.sh"
agent_init_metadata "resume-decide" "Analyzes logs to decide resume step"

# Required paths before agent can run
agent_required_paths() {
    echo "conversations"
    echo "worker.log"
}

# Output files that must exist (non-empty) after agent completes
agent_output_files() {
    echo "resume-step.txt"
    echo "resume-instructions.md"
}

# Source dependencies
agent_source_core
agent_source_once

# Main entry point
agent_run() {
    local worker_dir="$1"
    local project_dir="$2"
    local max_turns="${3:-10}"

    local conversations_dir="$worker_dir/conversations"
    local worker_log="$worker_dir/worker.log"

    log "Resume-decide agent analyzing previous run..."

    # Create standard directories
    agent_create_directories "$worker_dir"

    # Build the conversation context by reading all conversation files
    local conversation_text=""

    # Read iteration conversations in order
    if ls "$conversations_dir"/iteration-*.md >/dev/null 2>&1; then
        for conv_file in $(ls "$conversations_dir"/iteration-*.md | sort -t- -k2 -n); do
            [ -f "$conv_file" ] || continue
            conversation_text+="
=== $(basename "$conv_file" .md) ===

$(cat "$conv_file")

"
        done
    fi

    # Read sub-agent conversations
    for conv_file in "$conversations_dir"/*.md; do
        [ -f "$conv_file" ] || continue
        local base
        base=$(basename "$conv_file" .md)
        # Skip iteration files (already processed above)
        case "$base" in iteration-*) continue ;; esac
        conversation_text+="
=== $base ===

$(cat "$conv_file")

"
    done

    # Read worker.log for phase-level events
    local worker_log_text=""
    if [ -f "$worker_log" ]; then
        worker_log_text=$(cat "$worker_log")
    fi

    # Check if we have PRD to include status
    local prd_status=""
    if [ -f "$worker_dir/prd.md" ]; then
        prd_status=$(cat "$worker_dir/prd.md")
    fi

    # Build user prompt with all context
    local user_prompt
    user_prompt=$(_build_user_prompt "$conversation_text" "$worker_log_text" "$prd_status")

    # Run Claude once to get the decision
    local workspace="$worker_dir"
    [ -d "$worker_dir/workspace" ] && workspace="$worker_dir/workspace"

    run_agent_once "$workspace" \
        "$(_get_system_prompt)" \
        "$user_prompt" \
        "$worker_dir/logs/resume-decide.log" \
        "$max_turns"

    local agent_exit=$?

    # Extract decision from the log output
    _extract_decision "$worker_dir"

    if [ $agent_exit -ne 0 ]; then
        log_warn "Resume-decide agent exited with code $agent_exit"
    fi

    # Verify outputs exist
    if [ ! -f "$worker_dir/resume-step.txt" ] || [ ! -s "$worker_dir/resume-step.txt" ]; then
        log_error "resume-decide failed to produce resume-step.txt"
        echo "ABORT" > "$worker_dir/resume-step.txt"
        echo "Resume-decide agent failed to produce a decision." > "$worker_dir/resume-instructions.md"
        return 1
    fi

    local step
    step=$(cat "$worker_dir/resume-step.txt")
    log "Resume decision: $step"

    return 0
}

# System prompt for the resume-decide agent
_get_system_prompt() {
    cat << 'EOF'
RESUME DECISION AGENT

You are analyzing a previously interrupted worker run to decide where to resume from.

## Available Steps (in order)

1. `execution` - The main work loop (ralph loop iterations). Resume here means restarting the ENTIRE work loop from scratch. You cannot resume between iterations.
2. `audit` - Security audit phase
3. `test` - Test coverage phase
4. `docs` - Documentation writer phase
5. `validation` - Validation review phase
6. `finalization` - Commit/PR creation phase

## Decision Rules

- If the execution phase (ralph loop) was interrupted mid-iteration, you MUST resume from `execution` (you cannot resume between iterations)
- If execution completed successfully (all PRD tasks marked [x]) but a later phase failed or wasn't reached, resume from that phase
- If the worker failed due to a fundamental issue (bad PRD, impossible task, repeated failures), output ABORT
- If all phases completed successfully, output ABORT (nothing to resume)
- Prefer resuming from the earliest incomplete phase to ensure correctness

## How to Identify Phase Completion

- **execution complete**: worker.log shows "Task completed successfully" or PRD has all tasks marked [x]
- **audit complete**: worker.log shows "Security audit" result (PASS/FIX/STOP)
- **test complete**: worker.log shows "Test coverage result"
- **docs complete**: worker.log shows "Documentation writer result"
- **validation complete**: worker.log shows "validation review" ran
- **finalization complete**: worker.log shows "PR created" or "Commit created"

## Output Format

You MUST output your decision in these exact XML tags:

<step>STEP_NAME_OR_ABORT</step>

<instructions>
Detailed instructions for the resumed worker. Include:
- What was accomplished before the interruption
- What specifically needs to happen in the resumed phase
- Any important context from the previous run (patterns used, decisions made, files modified)
- Warnings about issues encountered in the previous run
</instructions>

## Important

- Be thorough in your analysis but decisive in your output
- The instructions will be injected into the resumed worker's prompt, so write them as guidance for a developer
- If the workspace has code changes from completed execution, those changes are preserved
EOF
}

# Build user prompt with conversation context
_build_user_prompt() {
    local conversation_text="$1"
    local worker_log_text="$2"
    local prd_status="$3"

    cat << EOF
Analyze the following worker run and decide which step to resume from.

## Worker Log (phase-level events)

\`\`\`
$worker_log_text
\`\`\`

## PRD Status

\`\`\`markdown
$prd_status
\`\`\`

## Conversation History

The following are the converted conversation logs from the previous run, showing what the worker did:

$conversation_text

---

Based on the above, determine:
1. Which phases completed successfully?
2. Where was the worker interrupted?
3. What step should we resume from (or should we ABORT)?

Provide your decision using the <step> and <instructions> tags as specified in the system prompt.
EOF
}

# Extract decision from resume-decide log output
_extract_decision() {
    local worker_dir="$1"
    local log_file="$worker_dir/logs/resume-decide.log"

    if [ ! -f "$log_file" ]; then
        log_error "No resume-decide log found"
        echo "ABORT" > "$worker_dir/resume-step.txt"
        echo "No decision log produced." > "$worker_dir/resume-instructions.md"
        return 1
    fi

    # Extract assistant text from stream-JSON
    local full_text
    full_text=$(grep '"type":"assistant"' "$log_file" | \
        jq -r 'select(.message.content[]? | .type == "text") | .message.content[] | select(.type == "text") | .text' 2>/dev/null || true)

    if [ -z "$full_text" ]; then
        log_error "No assistant text found in resume-decide log"
        echo "ABORT" > "$worker_dir/resume-step.txt"
        echo "Failed to extract decision from agent output." > "$worker_dir/resume-instructions.md"
        return 1
    fi

    # Extract step from <step>...</step> tags
    local step
    step=$(echo "$full_text" | sed -n 's/.*<step>\([^<]*\)<\/step>.*/\1/p' | head -1 | tr -d '[:space:]')

    if [ -z "$step" ]; then
        log_error "No <step> tag found in resume-decide output"
        echo "ABORT" > "$worker_dir/resume-step.txt"
        echo "Agent did not produce a step decision." > "$worker_dir/resume-instructions.md"
        return 1
    fi

    # Validate step name
    case "$step" in
        execution|audit|test|docs|validation|finalization|ABORT)
            echo "$step" > "$worker_dir/resume-step.txt"
            ;;
        *)
            log_error "Invalid step name from resume-decide: $step"
            echo "ABORT" > "$worker_dir/resume-step.txt"
            step="ABORT"
            ;;
    esac

    # Extract instructions from <instructions>...</instructions> tags
    local instructions
    instructions=$(echo "$full_text" | sed -n '/<instructions>/,/<\/instructions>/p' | sed '1d;$d')

    if [ -z "$instructions" ]; then
        instructions="Resuming from step: $step. No detailed instructions available."
    fi

    echo "$instructions" > "$worker_dir/resume-instructions.md"

    log "Extracted decision: step=$step"
    return 0
}
