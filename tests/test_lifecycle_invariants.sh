#!/usr/bin/env bash
set -euo pipefail
# test_lifecycle_invariants.sh - Property tests for lifecycle state machine invariants

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIGGUM_HOME="$(dirname "$TESTS_DIR")"
export WIGGUM_HOME

source "$TESTS_DIR/test-framework.sh"

# Source dependencies
source "$WIGGUM_HOME/lib/core/platform.sh"
source "$WIGGUM_HOME/lib/core/logger.sh"
source "$WIGGUM_HOME/lib/core/file-lock.sh"
source "$WIGGUM_HOME/lib/worker/git-state.sh"

LOG_LEVEL=ERROR
export LOG_LEVEL

TEST_DIR=""
WORKER_DIR=""
RALPH_DIR=""

setup() {
    TEST_DIR=$(mktemp -d)
    RALPH_DIR="$TEST_DIR/project/.ralph"
    WORKER_DIR="$RALPH_DIR/workers/worker-TASK-001-12345"
    mkdir -p "$WORKER_DIR"
    mkdir -p "$RALPH_DIR"
    export RALPH_DIR

    cat > "$RALPH_DIR/kanban.md" << 'KANBAN'
## In Progress
- [=] **[TASK-001]** Test task
  - Description: A test task
  - Priority: HIGH
  - Dependencies: none
KANBAN

    git_state_set "$WORKER_DIR" "none" "test" "Initial state"

    _LC_LOADED=0
    _LIFECYCLE_LOADER_LOADED=""
    _LIFECYCLE_ENGINE_LOADED=""
    _LIFECYCLE_GUARDS_LOADED=""
    source "$WIGGUM_HOME/lib/core/lifecycle-loader.sh"
    source "$WIGGUM_HOME/lib/core/lifecycle-engine.sh"
    source "$WIGGUM_HOME/lib/core/lifecycle-guards.sh"
}

teardown() {
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# =============================================================================
# Invariant 1: Terminal states reject non-recovery events
# =============================================================================

test_terminal_merged_rejects_events() {
    lifecycle_load
    git_state_set "$WORKER_DIR" "merged" "test" "Setup"

    local events=("fix.detected" "fix.started" "fix.pass" "merge.start" "merge.succeeded")
    local all_rejected=true

    for event in "${events[@]}"; do
        if emit_event "$WORKER_DIR" "$event" "test" '{}' 2>/dev/null; then
            echo "  Event $event was unexpectedly accepted from merged state"
            all_rejected=false
        fi
    done

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if $all_rejected; then
        echo -e "  ${GREEN}✓${NC} Terminal state 'merged' rejects all non-recovery events"
    else
        echo -e "  ${RED}✗${NC} Terminal state 'merged' should reject non-recovery events"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

test_terminal_failed_accepts_only_recovery() {
    lifecycle_load

    # Stub effects
    _check_permanent_failure() { return 0; }

    git_state_set "$WORKER_DIR" "failed" "test" "Setup"

    # Should reject regular events
    local rejected=true
    if emit_event "$WORKER_DIR" "fix.started" "test" '{}' 2>/dev/null; then
        rejected=false
    fi
    if emit_event "$WORKER_DIR" "merge.succeeded" "test" '{}' 2>/dev/null; then
        rejected=false
    fi

    # Reset state for recovery test
    git_state_set "$WORKER_DIR" "failed" "test" "Reset"

    # Should accept recovery events (when guard passes)
    local recovery_accepted=false
    if emit_event "$WORKER_DIR" "recovery.to_resolve" "test" '{}' 2>/dev/null; then
        recovery_accepted=true
    fi

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if $rejected && $recovery_accepted; then
        echo -e "  ${GREEN}✓${NC} Terminal 'failed' accepts only recovery events"
    else
        echo -e "  ${RED}✗${NC} Terminal 'failed' should accept only recovery events (rejected=$rejected, recovery_accepted=$recovery_accepted)"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

# =============================================================================
# Invariant 2: Wildcard transitions work from any non-terminal state
# =============================================================================

test_wildcard_resume_abort_from_all_states() {
    lifecycle_load

    # Stub effects
    github_issue_sync_task_status() { return 0; }

    local non_terminal_states=("none" "needs_fix" "fixing" "needs_merge" "merging" "needs_resolve" "resolving")
    local all_accepted=true

    for state in "${non_terminal_states[@]}"; do
        git_state_set "$WORKER_DIR" "$state" "test" "Setup for $state"

        if ! emit_event "$WORKER_DIR" "resume.abort" "test" '{}' 2>/dev/null; then
            echo "  resume.abort not accepted from state: $state"
            all_accepted=false
        fi

        # Verify transition to failed
        local new_state
        new_state=$(git_state_get "$WORKER_DIR")
        if [ "$new_state" != "failed" ]; then
            echo "  State after resume.abort from $state is $new_state, expected failed"
            all_accepted=false
        fi
    done

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if $all_accepted; then
        echo -e "  ${GREEN}✓${NC} Wildcard event 'resume.abort' works from all non-terminal states"
    else
        echo -e "  ${RED}✗${NC} Wildcard event should work from all non-terminal states"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

# =============================================================================
# Invariant 3: Guard ordering is correct (guarded transitions before fallbacks)
# =============================================================================

test_guard_ordering_first_match_wins() {
    lifecycle_load

    local spec_file="$WIGGUM_HOME/config/worker-lifecycle.json"

    # Find events that have both guarded and unguarded transitions from same state
    # The guarded one should come first in the array
    local all_correct=true

    # Check fix.pass from fixing - should have guarded (merge_attempts_lt_max) before fallback
    local fix_pass_transitions
    fix_pass_transitions=$(jq '[.transitions[] | select(.event == "fix.pass" and .from == "fixing")]' "$spec_file")
    local first_has_guard
    first_has_guard=$(echo "$fix_pass_transitions" | jq '.[0] | has("guard")')
    local second_has_guard
    second_has_guard=$(echo "$fix_pass_transitions" | jq '.[1] | has("guard")')

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if [ "$first_has_guard" = "true" ] && [ "$second_has_guard" = "false" ]; then
        echo -e "  ${GREEN}✓${NC} fix.pass: guarded transition comes before fallback"
    else
        echo -e "  ${RED}✗${NC} fix.pass: guarded transition should come before fallback"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        all_correct=false
    fi

    # Check merge.start from needs_merge
    local merge_start_transitions
    merge_start_transitions=$(jq '[.transitions[] | select(.event == "merge.start" and .from == "needs_merge")]' "$spec_file")
    first_has_guard=$(echo "$merge_start_transitions" | jq '.[0] | has("guard")')
    second_has_guard=$(echo "$merge_start_transitions" | jq '.[1] | has("guard")')

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if [ "$first_has_guard" = "true" ] && [ "$second_has_guard" = "false" ]; then
        echo -e "  ${GREEN}✓${NC} merge.start: guarded transition comes before fallback"
    else
        echo -e "  ${RED}✗${NC} merge.start: guarded transition should come before fallback"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

# =============================================================================
# Invariant 4: Transient states never remain as final state
# =============================================================================

test_transient_states_always_chain() {
    lifecycle_load

    local transient_states=("fix_completed" "merge_conflict" "resolved")

    for state in "${transient_states[@]}"; do
        local state_type
        state_type=$(lifecycle_state_type "$state")

        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        if [ "$state_type" = "transient" ] || [ "$state_type" = "waiting" ]; then
            echo -e "  ${GREEN}✓${NC} State '$state' is correctly typed as transient/waiting"
        else
            echo -e "  ${RED}✗${NC} State '$state' should be transient, got: $state_type"
            FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        fi
    done
}

test_transient_states_have_chain_property() {
    lifecycle_load

    local spec_file="$WIGGUM_HOME/config/worker-lifecycle.json"

    # Transitions that use chain should reference transient states
    local chain_transitions
    chain_transitions=$(jq '[.transitions[] | select(.chain != null) | .chain] | unique | .[]' "$spec_file")

    for chain_state in $chain_transitions; do
        local state_type
        state_type=$(lifecycle_state_type "$chain_state")

        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        if [ "$state_type" = "transient" ]; then
            echo -e "  ${GREEN}✓${NC} Chain state '$chain_state' is transient"
        else
            echo -e "  ${RED}✗${NC} Chain state '$chain_state' should be transient, got: $state_type"
            FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        fi
    done
}

# =============================================================================
# Invariant 5: Running states reset on startup
# =============================================================================

test_running_states_reset_on_startup() {
    lifecycle_load

    local running_states=("fixing" "merging")

    for state in "${running_states[@]}"; do
        git_state_set "$WORKER_DIR" "$state" "test" "Setup"

        local result=0
        emit_event "$WORKER_DIR" "startup.reset" "test" '{}' 2>/dev/null || result=$?

        local new_state
        new_state=$(git_state_get "$WORKER_DIR")

        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        case "$state" in
            fixing)
                if [ "$new_state" = "needs_fix" ]; then
                    echo -e "  ${GREEN}✓${NC} 'fixing' resets to 'needs_fix'"
                else
                    echo -e "  ${RED}✗${NC} 'fixing' should reset to 'needs_fix', got: $new_state"
                    FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
                fi
                ;;
            merging)
                if [ "$new_state" = "needs_merge" ]; then
                    echo -e "  ${GREEN}✓${NC} 'merging' resets to 'needs_merge'"
                else
                    echo -e "  ${RED}✗${NC} 'merging' should reset to 'needs_merge', got: $new_state"
                    FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
                fi
                ;;
        esac
    done
}

test_resolving_resets_via_resolve_startup_reset() {
    lifecycle_load

    git_state_set "$WORKER_DIR" "resolving" "test" "Setup"

    emit_event "$WORKER_DIR" "resolve.startup_reset" "test" '{}' 2>/dev/null || true

    local new_state
    new_state=$(git_state_get "$WORKER_DIR")

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if [ "$new_state" = "needs_resolve" ]; then
        echo -e "  ${GREEN}✓${NC} 'resolving' resets to 'needs_resolve' via resolve.startup_reset"
    else
        echo -e "  ${RED}✗${NC} 'resolving' should reset to 'needs_resolve', got: $new_state"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

# =============================================================================
# Invariant 6: Non-terminal states have outbound transitions
# =============================================================================

test_non_terminal_states_have_transitions() {
    lifecycle_load

    local spec_file="$WIGGUM_HOME/config/worker-lifecycle.json"

    # Get all non-terminal states
    local states
    states=$(jq -r '.states | to_entries[] | select(.value.type != "terminal") | .key' "$spec_file")

    for state in $states; do
        # Check if any transition has this state as 'from' (or wildcard)
        local has_transition
        has_transition=$(jq --arg s "$state" '[.transitions[] | select(.from == $s or .from == "*")] | length' "$spec_file")
        has_transition="${has_transition:-0}"

        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        if [ "$has_transition" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} State '$state' has outbound transitions"
        else
            echo -e "  ${RED}✗${NC} State '$state' has no outbound transitions"
            FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        fi
    done
}

# =============================================================================
# Invariant 7: Guard functions exist for all referenced guards
# =============================================================================

test_all_guards_have_implementations() {
    lifecycle_load

    local spec_file="$WIGGUM_HOME/config/worker-lifecycle.json"

    # Get all unique guard names from spec
    local guards
    guards=$(jq -r '[.transitions[].guard // empty] | unique | .[]' "$spec_file")

    for guard in $guards; do
        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        if [ -n "${_LC_GUARD_FN[$guard]:-}" ]; then
            echo -e "  ${GREEN}✓${NC} Guard '$guard' has implementation"
        else
            echo -e "  ${RED}✗${NC} Guard '$guard' missing implementation"
            FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        fi
    done
}

# =============================================================================
# Invariant 8: Effect functions exist for all referenced effects
# =============================================================================

test_all_effects_have_implementations() {
    lifecycle_load

    local spec_file="$WIGGUM_HOME/config/worker-lifecycle.json"

    # Get all unique effect names from spec
    local effects
    effects=$(jq -r '[.transitions[].effects[]? // empty] | unique | .[]' "$spec_file")

    for effect in $effects; do
        ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
        if [ -n "${_LC_EFFECT_FN[$effect]:-}" ]; then
            echo -e "  ${GREEN}✓${NC} Effect '$effect' has implementation"
        else
            echo -e "  ${RED}✗${NC} Effect '$effect' missing implementation"
            FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
        fi
    done
}

# =============================================================================
# Run All Tests
# =============================================================================

run_test test_terminal_merged_rejects_events
run_test test_terminal_failed_accepts_only_recovery
run_test test_wildcard_resume_abort_from_all_states
run_test test_guard_ordering_first_match_wins
run_test test_transient_states_always_chain
run_test test_transient_states_have_chain_property
run_test test_running_states_reset_on_startup
run_test test_resolving_resets_via_resolve_startup_reset
run_test test_non_terminal_states_have_transitions
run_test test_all_guards_have_implementations
run_test test_all_effects_have_implementations

print_test_summary
exit_with_test_result
