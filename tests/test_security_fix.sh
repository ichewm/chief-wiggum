#!/usr/bin/env bash
# Test suite for security-fix agent
# Tests: _find_security_audit_report helper, step-config handling

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
    mkdir -p "$TEST_TMP_DIR/reports"
}

teardown() {
    if [ -n "$TEST_TMP_DIR" ] && [ -d "$TEST_TMP_DIR" ]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# =============================================================================
# Test: Bash Syntax Validation
# =============================================================================

test_security_fix_sh_syntax() {
    if bash -n "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh" 2>/dev/null; then
        assert_success "security-fix.sh should have valid bash syntax" true
    else
        assert_failure "security-fix.sh should have valid bash syntax" true
    fi
}

# =============================================================================
# Test: _find_security_audit_report Helper
# =============================================================================

test_find_security_audit_report_finds_critical() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a report with CRITICAL findings
    cat > "$TEST_TMP_DIR/reports/1234567890-audit-report.md" << 'EOF'
# Security Audit Report

### CRITICAL
- **[SEC-001]** SQL Injection vulnerability

### HIGH
- **[SEC-002]** XSS vulnerability
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report with CRITICAL findings"
    assert_file_exists "$result" "Report file should exist"
}

test_find_security_audit_report_finds_high() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a report with only HIGH findings
    cat > "$TEST_TMP_DIR/reports/1234567890-security-report.md" << 'EOF'
# Security Audit Report

### HIGH
- **[SEC-001]** Hardcoded credentials
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report with HIGH findings"
}

test_find_security_audit_report_finds_medium() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a report with only MEDIUM findings
    cat > "$TEST_TMP_DIR/reports/1234567890-scan-report.md" << 'EOF'
# Security Scan

### MEDIUM
- **[SEC-001]** Weak password policy
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report with MEDIUM findings"
}

test_find_security_audit_report_finds_low() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a report with only LOW findings
    cat > "$TEST_TMP_DIR/reports/1234567890-analysis-report.md" << 'EOF'
# Analysis

### LOW
- Minor issue
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report with LOW findings"
}

test_find_security_audit_report_finds_info() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a report with only INFO findings
    cat > "$TEST_TMP_DIR/reports/1234567890-info-report.md" << 'EOF'
# Informational

### INFO
- Informational note
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report with INFO findings"
}

test_find_security_audit_report_ignores_non_security() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create a non-security report
    cat > "$TEST_TMP_DIR/reports/1234567890-code-review-report.md" << 'EOF'
# Code Review Report

## Summary
Code looks good.

## Recommendations
- Add more tests
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should not find non-security reports"
}

test_find_security_audit_report_returns_most_recent() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create an older security report
    cat > "$TEST_TMP_DIR/reports/1000000000-old-report.md" << 'EOF'
# Old Report
### CRITICAL
- Old finding
EOF
    # Set older modification time
    touch -d "2020-01-01" "$TEST_TMP_DIR/reports/1000000000-old-report.md"

    # Create a newer security report
    cat > "$TEST_TMP_DIR/reports/2000000000-new-report.md" << 'EOF'
# New Report
### HIGH
- New finding
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_output_contains "$result" "new-report" "Should return most recent security report"
}

test_find_security_audit_report_empty_reports_dir() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Empty reports directory (already created in setup)
    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should return empty for empty reports dir"
}

test_find_security_audit_report_no_reports_dir() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Remove reports directory
    rm -rf "$TEST_TMP_DIR/reports"

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_equals "" "$result" "Should return empty when no reports dir"
}

test_find_security_audit_report_step_id_agnostic() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"
    source "$WIGGUM_HOME/lib/agents/engineering/security-fix.sh"

    # Create report with arbitrary step ID in filename
    cat > "$TEST_TMP_DIR/reports/1234567890-custom-step-name-report.md" << 'EOF'
# Security Report
### CRITICAL
- Finding
EOF

    local result
    result=$(_find_security_audit_report "$TEST_TMP_DIR")

    assert_not_equals "" "$result" "Should find report regardless of step ID in filename"
}

# =============================================================================
# Test: Step-based report lookup
# =============================================================================

test_agent_find_latest_report_by_step_id() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"

    # Create a report file named by step ID
    cat > "$TEST_TMP_DIR/reports/1234567890-audit-report.md" << 'EOF'
# Report content
EOF

    local result
    result=$(agent_find_latest_report "$TEST_TMP_DIR" "audit")

    assert_not_equals "" "$result" "Should find report by step ID"
    assert_file_exists "$result" "Report file should exist"
}

test_agent_find_latest_report_not_found_by_agent_type() {
    source "$WIGGUM_HOME/lib/core/agent-base.sh"

    # Create a report file named by step ID
    cat > "$TEST_TMP_DIR/reports/1234567890-audit-report.md" << 'EOF'
# Report content
EOF

    # Try to find by agent type (should fail - files named by step ID)
    local result
    result=$(agent_find_latest_report "$TEST_TMP_DIR" "security-audit")

    assert_equals "" "$result" "Should NOT find report by agent type when file named by step ID"
}

# =============================================================================
# Run Tests
# =============================================================================

# Syntax validation
run_test test_security_fix_sh_syntax

# _find_security_audit_report helper
run_test test_find_security_audit_report_finds_critical
run_test test_find_security_audit_report_finds_high
run_test test_find_security_audit_report_finds_medium
run_test test_find_security_audit_report_finds_low
run_test test_find_security_audit_report_finds_info
run_test test_find_security_audit_report_ignores_non_security
run_test test_find_security_audit_report_returns_most_recent
run_test test_find_security_audit_report_empty_reports_dir
run_test test_find_security_audit_report_no_reports_dir
run_test test_find_security_audit_report_step_id_agnostic

# Step-based report lookup
run_test test_agent_find_latest_report_by_step_id
run_test test_agent_find_latest_report_not_found_by_agent_type

# Print summary
print_test_summary
exit_with_test_result
