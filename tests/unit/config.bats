#!/usr/bin/env bats
# tests/unit/config.bats - Unit tests for lib/config.sh

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    # Clear environment variables before each test
    unset CJ_PROFILE CJ_NETWORK CJ_SANDBOX_HOME CJ_COPY_CLAUDE_CONFIG CJ_VERBOSE
    unset CJ_EXTRA_RO CJ_EXTRA_RW CJ_BLOCKED CJ_CONFIG_FILE
    source_config
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# cj::config::init tests
# =============================================================================

@test "cj::config::init sets default values" {
    # Defaults are set when config.sh is sourced (in setup)
    # init() only adds environment variable overrides

    assert_equal "$(cj::config::get profile)" "standard"
    assert_equal "$(cj::config::get network)" "true"
    assert_equal "$(cj::config::get sandbox_home)" ".claude-sandbox"
}

@test "cj::config::init respects CJ_PROFILE environment variable" {
    export CJ_PROFILE="paranoid"

    cj::config::init

    assert_equal "$(cj::config::get profile)" "paranoid"
}

@test "cj::config::init respects CJ_NETWORK environment variable" {
    export CJ_NETWORK="false"

    cj::config::init

    assert_equal "$(cj::config::get network)" "false"
}

@test "cj::config::init respects CJ_SANDBOX_HOME environment variable" {
    export CJ_SANDBOX_HOME=".my-sandbox"

    cj::config::init

    assert_equal "$(cj::config::get sandbox_home)" ".my-sandbox"
}

@test "cj::config::init parses CJ_EXTRA_RO colon-separated paths" {
    export CJ_EXTRA_RO="/path/one:/path/two:/path/three"

    cj::config::init

    run cj::config::get_extra_ro
    assert_output --partial "/path/one"
    assert_output --partial "/path/two"
    assert_output --partial "/path/three"
}

@test "cj::config::init parses CJ_EXTRA_RW colon-separated paths" {
    export CJ_EXTRA_RW="/rw/one:/rw/two"

    cj::config::init

    run cj::config::get_extra_rw
    assert_output --partial "/rw/one"
    assert_output --partial "/rw/two"
}

# =============================================================================
# cj::config::_load_file tests
# =============================================================================

@test "cj::config::_load_file returns failure for non-existent file" {
    run cj::config::_load_file "/nonexistent/config/file"
    assert_failure
}

@test "cj::config::_load_file loads valid config file" {
    local config_file="$TEST_TMPDIR/config"
    cat > "$config_file" <<'EOF'
CJ_PROFILE=dev
CJ_NETWORK=false
EOF

    cj::config::_load_file "$config_file"
    cj::config::init

    assert_equal "$(cj::config::get profile)" "dev"
    assert_equal "$(cj::config::get network)" "false"
}

@test "cj::config::_load_file warns on invalid syntax" {
    local config_file="$TEST_TMPDIR/bad_config"
    # Create invalid bash syntax
    echo "this is not valid bash {{{" > "$config_file"

    run cj::config::_load_file "$config_file"
    assert_failure
    assert_output --partial "Warning"
}

# =============================================================================
# cj::config::get tests
# =============================================================================

@test "cj::config::get returns default when key not set" {
    _CJ_CONFIG[testkey]=""

    run cj::config::get testkey "default_value"
    assert_success
    assert_output "default_value"
}

@test "cj::config::get returns value when key is set" {
    _CJ_CONFIG[testkey]="actual_value"

    run cj::config::get testkey "default_value"
    assert_success
    assert_output "actual_value"
}

# =============================================================================
# cj::config::get_bool tests
# =============================================================================

@test "cj::config::get_bool returns true for 'true'" {
    _CJ_CONFIG[boolkey]="true"

    cj::config::get_bool boolkey false
    assert_equal "$?" 0
}

@test "cj::config::get_bool returns true for 'yes'" {
    _CJ_CONFIG[boolkey]="yes"

    cj::config::get_bool boolkey false
    assert_equal "$?" 0
}

@test "cj::config::get_bool returns true for '1'" {
    _CJ_CONFIG[boolkey]="1"

    cj::config::get_bool boolkey false
    assert_equal "$?" 0
}

@test "cj::config::get_bool returns false for 'false'" {
    _CJ_CONFIG[boolkey]="false"

    run bash -c 'cj::config::get_bool boolkey true && echo yes || echo no'
    # This is a bit awkward because get_bool uses return code
    if cj::config::get_bool boolkey true; then
        fail "Expected false but got true"
    fi
}

@test "cj::config::get_bool uses default when key not set" {
    _CJ_CONFIG[boolkey]=""

    if cj::config::get_bool boolkey true; then
        # Default is true, should succeed
        true
    else
        fail "Expected default true but got false"
    fi
}

# =============================================================================
# cj::config::set tests
# =============================================================================

@test "cj::config::set updates config value" {
    cj::config::set mykey "myvalue"

    assert_equal "${_CJ_CONFIG[mykey]}" "myvalue"
}

@test "cj::config::set overwrites existing value" {
    _CJ_CONFIG[mykey]="oldvalue"

    cj::config::set mykey "newvalue"

    assert_equal "${_CJ_CONFIG[mykey]}" "newvalue"
}

# =============================================================================
# cj::config::add_extra_ro and cj::config::add_extra_rw tests
# =============================================================================

@test "cj::config::add_extra_ro appends to extra RO paths" {
    _CJ_EXTRA_RO=()

    cj::config::add_extra_ro "/new/path"

    assert_array_contains _CJ_EXTRA_RO "/new/path"
}

@test "cj::config::add_extra_rw appends to extra RW paths" {
    _CJ_EXTRA_RW=()

    cj::config::add_extra_rw "/new/rw/path"

    assert_array_contains _CJ_EXTRA_RW "/new/rw/path"
}

# =============================================================================
# cj::config::show tests
# =============================================================================

@test "cj::config::show displays configuration" {
    run cj::config::show

    assert_success
    assert_output --partial "profile:"
    assert_output --partial "network:"
    assert_output --partial "sandbox-home:"
}

# =============================================================================
# cj::config::help tests
# =============================================================================

@test "cj::config::help displays help text" {
    run cj::config::help

    assert_success
    assert_output --partial "CONFIGURATION"
    assert_output --partial "CJ_PROFILE"
    assert_output --partial "Environment variables"
}

# =============================================================================
# Config file precedence tests
# =============================================================================

@test "environment variable overrides config file" {
    local config_file="$TEST_TMPDIR/config"
    echo "CJ_PROFILE=minimal" > "$config_file"
    export CJ_CONFIG_FILE="$config_file"
    export CJ_PROFILE="paranoid"

    cj::config::init

    # Environment should win
    assert_equal "$(cj::config::get profile)" "paranoid"
}

@test "config file overrides default" {
    local config_file="$TEST_TMPDIR/config"
    echo "CJ_PROFILE=dev" > "$config_file"

    # Manually source and re-init to simulate config file loading
    source "$config_file"
    cj::config::init

    assert_equal "$(cj::config::get profile)" "dev"
}
