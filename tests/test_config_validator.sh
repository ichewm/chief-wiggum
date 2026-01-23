#!/usr/bin/env bash
# Tests for lib/core/config-validator.sh

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIGGUM_HOME="$(dirname "$TESTS_DIR")"
export WIGGUM_HOME

source "$TESTS_DIR/test-framework.sh"
source "$WIGGUM_HOME/lib/core/logger.sh"
source "$WIGGUM_HOME/lib/core/config-validator.sh"

TEST_DIR=""
setup() {
    TEST_DIR=$(mktemp -d)
    export LOG_FILE="$TEST_DIR/test.log"
}
teardown() {
    rm -rf "$TEST_DIR"
}

# ===========================================================================
# Test: Valid JSON file passes
# ===========================================================================
test_valid_json_file_passes() {
    cat > "$TEST_DIR/valid.json" << 'JSON'
{
    "key": "value",
    "number": 42
}
JSON
    assert_success "validate_json_file '$TEST_DIR/valid.json'" \
        "Valid JSON file should pass validation"
}

# ===========================================================================
# Test: Non-existent file fails
# ===========================================================================
test_nonexistent_file_fails() {
    assert_failure "validate_json_file '$TEST_DIR/nonexistent.json'" \
        "Non-existent file should fail validation"
}

# ===========================================================================
# Test: Invalid JSON syntax fails
# ===========================================================================
test_invalid_json_syntax_fails() {
    cat > "$TEST_DIR/bad.json" << 'JSON'
{
    "key": "value",
    "missing_closing_brace": true
JSON
    assert_failure "validate_json_file '$TEST_DIR/bad.json'" \
        "Invalid JSON syntax should fail validation"
}

# ===========================================================================
# Test: Valid config.json with all sections passes
# ===========================================================================
test_valid_config_passes() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": {
        "max_iterations": 50,
        "sleep_seconds": 2
    },
    "hooks": {
        "enabled": true
    },
    "paths": {
        "log_dir": "/var/log/wiggum"
    },
    "review": {
        "fix_max_iterations": 10,
        "fix_max_turns": 30,
        "approved_authors": ["alice", "bob"]
    }
}
JSON
    assert_success "validate_config '$TEST_DIR/config.json'" \
        "Valid config.json with all sections should pass"
}

# ===========================================================================
# Test: Config with out-of-range max_iterations fails
# ===========================================================================
test_config_max_iterations_out_of_range() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": {
        "max_iterations": 200,
        "sleep_seconds": 2
    },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {}
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "workers.max_iterations=200 should fail (max 100)"

    cat > "$TEST_DIR/config2.json" << 'JSON'
{
    "workers": {
        "max_iterations": 0,
        "sleep_seconds": 2
    },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {}
}
JSON
    assert_failure "validate_config '$TEST_DIR/config2.json'" \
        "workers.max_iterations=0 should fail (min 1)"
}

# ===========================================================================
# Test: Config with out-of-range sleep_seconds fails
# ===========================================================================
test_config_sleep_seconds_out_of_range() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": {
        "max_iterations": 50,
        "sleep_seconds": 100
    },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {}
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "workers.sleep_seconds=100 should fail (max 60)"
}

# ===========================================================================
# Test: Config with non-boolean hooks.enabled fails
# ===========================================================================
test_config_hooks_enabled_non_boolean() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": { "max_iterations": 50, "sleep_seconds": 2 },
    "hooks": {
        "enabled": "yes"
    },
    "paths": {},
    "review": {}
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "hooks.enabled='yes' (non-boolean) should fail"
}

# ===========================================================================
# Test: Config with out-of-range review.fix_max_iterations fails
# ===========================================================================
test_config_fix_max_iterations_out_of_range() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": { "max_iterations": 50, "sleep_seconds": 2 },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {
        "fix_max_iterations": 100,
        "fix_max_turns": 30
    }
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "review.fix_max_iterations=100 should fail (max 50)"
}

# ===========================================================================
# Test: Config with out-of-range review.fix_max_turns fails
# ===========================================================================
test_config_fix_max_turns_out_of_range() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": { "max_iterations": 50, "sleep_seconds": 2 },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {
        "fix_max_iterations": 10,
        "fix_max_turns": 200
    }
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "review.fix_max_turns=200 should fail (max 100)"
}

# ===========================================================================
# Test: Config with non-array approved_authors fails
# ===========================================================================
test_config_approved_authors_non_array() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": { "max_iterations": 50, "sleep_seconds": 2 },
    "hooks": { "enabled": true },
    "paths": {},
    "review": {
        "fix_max_iterations": 10,
        "fix_max_turns": 30,
        "approved_authors": "alice"
    }
}
JSON
    assert_failure "validate_config '$TEST_DIR/config.json'" \
        "review.approved_authors as string should fail (must be array)"
}

# ===========================================================================
# Test: Unknown top-level keys get warned but pass
# ===========================================================================
test_config_unknown_keys_warn_but_pass() {
    cat > "$TEST_DIR/config.json" << 'JSON'
{
    "workers": { "max_iterations": 50, "sleep_seconds": 2 },
    "hooks": { "enabled": true },
    "paths": {},
    "review": { "fix_max_iterations": 10, "fix_max_turns": 30 },
    "unknown_section": { "foo": "bar" }
}
JSON
    assert_success "validate_config '$TEST_DIR/config.json'" \
        "Unknown top-level key should warn but still pass"

    assert_file_contains "$TEST_DIR/test.log" "Unknown config key: unknown_section" \
        "Log should contain warning about unknown key"
}

# ===========================================================================
# Test: Valid agents.json passes
# ===========================================================================
test_valid_agents_config_passes() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "max_iterations": 50,
            "max_turns": 100,
            "timeout_seconds": 3600,
            "supervisor_interval": 5,
            "max_restarts": 3,
            "auto_commit": true
        },
        "review-agent": {
            "max_iterations": 10,
            "max_turns": 30,
            "timeout_seconds": 1800,
            "auto_commit": false
        }
    },
    "defaults": {
        "max_iterations": 30,
        "max_turns": 50,
        "timeout_seconds": 3600,
        "supervisor_interval": 3,
        "max_restarts": 2,
        "auto_commit": false
    }
}
JSON
    assert_success "validate_agents_config '$TEST_DIR/agents.json'" \
        "Valid agents.json should pass validation"
}

# ===========================================================================
# Test: Missing agents section fails
# ===========================================================================
test_agents_missing_agents_section() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Missing agents section should fail"
}

# ===========================================================================
# Test: Missing defaults section fails
# ===========================================================================
test_agents_missing_defaults_section() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "max_iterations": 50
        }
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Missing defaults section should fail"
}

# ===========================================================================
# Test: Invalid agent name format fails (uppercase)
# ===========================================================================
test_agents_invalid_name_uppercase() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "CodeWorker": {
            "max_iterations": 50
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Uppercase agent name should fail"
}

# ===========================================================================
# Test: Invalid agent name format fails (special chars)
# ===========================================================================
test_agents_invalid_name_special_chars() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code_worker!": {
            "max_iterations": 50
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent name with special chars should fail"
}

# ===========================================================================
# Test: Agent with max_iterations out of range fails
# ===========================================================================
test_agents_max_iterations_out_of_range() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "max_iterations": 150
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent max_iterations=150 should fail (max 100)"
}

# ===========================================================================
# Test: Agent with max_turns out of range fails
# ===========================================================================
test_agents_max_turns_out_of_range() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "max_turns": 300
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent max_turns=300 should fail (max 200)"
}

# ===========================================================================
# Test: Agent with timeout_seconds out of range fails
# ===========================================================================
test_agents_timeout_seconds_out_of_range() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "timeout_seconds": 10
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent timeout_seconds=10 should fail (min 60)"

    cat > "$TEST_DIR/agents2.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "timeout_seconds": 100000
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents2.json'" \
        "Agent timeout_seconds=100000 should fail (max 86400)"
}

# ===========================================================================
# Test: Agent with supervisor_interval out of range fails
# ===========================================================================
test_agents_supervisor_interval_out_of_range() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "supervisor_interval": 25
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent supervisor_interval=25 should fail (max 20)"
}

# ===========================================================================
# Test: Agent with max_restarts out of range fails
# ===========================================================================
test_agents_max_restarts_out_of_range() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "max_restarts": 50
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent max_restarts=50 should fail (max 10)"
}

# ===========================================================================
# Test: Agent with non-boolean auto_commit fails
# ===========================================================================
test_agents_auto_commit_non_boolean() {
    cat > "$TEST_DIR/agents.json" << 'JSON'
{
    "agents": {
        "code-worker": {
            "auto_commit": "yes"
        }
    },
    "defaults": {
        "max_iterations": 30
    }
}
JSON
    assert_failure "validate_agents_config '$TEST_DIR/agents.json'" \
        "Agent auto_commit='yes' (non-boolean) should fail"
}

# ===========================================================================
# Run all tests
# ===========================================================================
run_test test_valid_json_file_passes
run_test test_nonexistent_file_fails
run_test test_invalid_json_syntax_fails
run_test test_valid_config_passes
run_test test_config_max_iterations_out_of_range
run_test test_config_sleep_seconds_out_of_range
run_test test_config_hooks_enabled_non_boolean
run_test test_config_fix_max_iterations_out_of_range
run_test test_config_fix_max_turns_out_of_range
run_test test_config_approved_authors_non_array
run_test test_config_unknown_keys_warn_but_pass
run_test test_valid_agents_config_passes
run_test test_agents_missing_agents_section
run_test test_agents_missing_defaults_section
run_test test_agents_invalid_name_uppercase
run_test test_agents_invalid_name_special_chars
run_test test_agents_max_iterations_out_of_range
run_test test_agents_max_turns_out_of_range
run_test test_agents_timeout_seconds_out_of_range
run_test test_agents_supervisor_interval_out_of_range
run_test test_agents_max_restarts_out_of_range
run_test test_agents_auto_commit_non_boolean

print_test_summary
exit_with_test_result
