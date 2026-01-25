#!/usr/bin/env bash
# Test suite for task-summarizer agent
# Tests: _find_result_with_session_id helper, step-config handling

set -euo pipefail

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/test-framework.sh"

# Setup WIGGUM_HOME for tests
export WIGGUM_HOME="$PROJECT_ROOT"

# Temporary directory for test files
TEST_TMP_DIR=""

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    TEST_TMP_DIR=$(mktemp -d)
    mkdir -p "$TEST_TMP_DIR/results"
}

teardown() {
    if [ -n "$TEST_TMP_DIR" ] && [ -d "$TEST_TMP_DIR" ]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# =============================================================================
# Test: Bash Syntax Validation
# =============================================================================

test_task_summarizer_sh_syntax() {
    if bash -n "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh" 2>/dev/null; then
        assert_success "task-summarizer.sh should have valid bash syntax" true
    else
        assert_failure "task-summarizer.sh should have valid bash syntax" true
    fi
}

# =============================================================================
# Test: _find_result_with_session_id Helper
# =============================================================================

test_find_result_with_session_id_finds_file() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Create a result file with session_id
    cat > "$TEST_TMP_DIR/results/1234567890-execution-result.json" << 'EOF'
{
  "agent_type": "system.task-executor",
  "status": "success",
  "outputs": {
    "session_id": "abc123-test-session",
    "gate_result": "PASS"
  }
}
EOF

    local result
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find a result file"
    assert_file_exists "$result" "Result file should exist"
}

test_find_result_with_session_id_extracts_session() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Create a result file with session_id
    cat > "$TEST_TMP_DIR/results/1234567890-mystep-result.json" << 'EOF'
{
  "outputs": {
    "session_id": "test-session-uuid-12345"
  }
}
EOF

    local result session_id
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")
    session_id=$(jq -r '.outputs.session_id' "$result")

    assert_equals "test-session-uuid-12345" "$session_id" "Should extract correct session_id"
}

test_find_result_with_session_id_ignores_files_without_session() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Create a result file WITHOUT session_id
    cat > "$TEST_TMP_DIR/results/1234567890-audit-result.json" << 'EOF'
{
  "agent_type": "engineering.security-audit",
  "outputs": {
    "gate_result": "PASS"
  }
}
EOF

    local result
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should return empty when no session_id found"
}

test_find_result_with_session_id_returns_most_recent() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Create an older result file
    cat > "$TEST_TMP_DIR/results/1000000000-old-result.json" << 'EOF'
{
  "outputs": { "session_id": "old-session" }
}
EOF
    # Set older modification time
    touch -d "2020-01-01" "$TEST_TMP_DIR/results/1000000000-old-result.json"

    # Create a newer result file
    cat > "$TEST_TMP_DIR/results/2000000000-new-result.json" << 'EOF'
{
  "outputs": { "session_id": "new-session" }
}
EOF

    local result session_id
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")
    session_id=$(jq -r '.outputs.session_id' "$result")

    assert_equals "new-session" "$session_id" "Should return most recent file"
}

test_find_result_with_session_id_empty_results_dir() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Empty results directory (already created in setup)
    local result
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should return empty for empty results dir"
}

test_find_result_with_session_id_no_results_dir() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Remove results directory
    rm -rf "$TEST_TMP_DIR/results"

    local result
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should return empty when no results dir"
}

test_find_result_with_session_id_skips_empty_session() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/system/task-summarizer.sh"

    # Create a result file with empty session_id
    cat > "$TEST_TMP_DIR/results/1234567890-step-result.json" << 'EOF'
{
  "outputs": {
    "session_id": "",
    "gate_result": "PASS"
  }
}
EOF

    local result
    result=$(_find_result_with_session_id "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should skip files with empty session_id"
}

# =============================================================================
# Test: Step-based result lookup
# =============================================================================

test_agent_find_latest_result_by_step_id() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"

    # Create a result file named by step ID
    cat > "$TEST_TMP_DIR/results/1234567890-execution-result.json" << 'EOF'
{
  "outputs": { "session_id": "test-session" }
}
EOF

    local result
    result=$(agent_find_latest_result "$TEST_TMP_DIR" "execution")

    assert_not_equals "" "$result" "Should find result by step ID"
    assert_file_exists "$result" "Result file should exist"
}

test_agent_find_latest_result_not_found_by_agent_type() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"

    # Create a result file named by step ID
    cat > "$TEST_TMP_DIR/results/1234567890-execution-result.json" << 'EOF'
{
  "agent_type": "system.task-executor",
  "outputs": { "session_id": "test-session" }
}
EOF

    # Try to find by agent type (should fail - files named by step ID)
    local result
    result=$(agent_find_latest_result "$TEST_TMP_DIR" "task-executor")

    assert_equals "" "$result" "Should NOT find result by agent type when file named by step ID"
}

# =============================================================================
# Run Tests
# =============================================================================

# Syntax validation
run_test test_task_summarizer_sh_syntax

# _find_result_with_session_id helper
run_test test_find_result_with_session_id_finds_file
run_test test_find_result_with_session_id_extracts_session
run_test test_find_result_with_session_id_ignores_files_without_session
run_test test_find_result_with_session_id_returns_most_recent
run_test test_find_result_with_session_id_empty_results_dir
run_test test_find_result_with_session_id_no_results_dir
run_test test_find_result_with_session_id_skips_empty_session

# Step-based result lookup
run_test test_agent_find_latest_result_by_step_id
run_test test_agent_find_latest_result_not_found_by_agent_type

# Print summary
print_test_summary
exit_with_test_result
