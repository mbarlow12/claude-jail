#!/usr/bin/env bats
# tests/unit/sandbox_home.bats - Unit tests for sandbox home resolution

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    # Clear environment variables before each test
    unset CJ_PROFILE CJ_NETWORK CJ_SANDBOX_HOME CJ_SANDBOX_NAME
    unset CJ_COPY_CLAUDE_CONFIG CJ_VERBOSE CJ_GIT_WORKTREE_RO
    unset CJ_EXTRA_RO CJ_EXTRA_RW CJ_BLOCKED CJ_CONFIG_FILE
    source_sandbox
    # Reset config to defaults
    _CJ_CONFIG[sandbox_home]=".claude-sandbox"
    _CJ_CONFIG[sandbox_name]=".claude-sandbox"
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# cj::sandbox::resolve_home tests
# =============================================================================

@test "cj::sandbox::resolve_home uses cwd by default" {
    cd "$TEST_TMPDIR"

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$TEST_TMPDIR/.claude-sandbox"
}

@test "cj::sandbox::resolve_home respects parent override" {
    local parent="$TEST_TMPDIR/custom-parent"
    mkdir -p "$parent"

    run cj::sandbox::resolve_home "$parent"
    assert_success
    assert_output "$parent/.claude-sandbox"
}

@test "cj::sandbox::resolve_home respects name override" {
    cd "$TEST_TMPDIR"

    run cj::sandbox::resolve_home "" ".my-sandbox"
    assert_success
    assert_output "$TEST_TMPDIR/.my-sandbox"
}

@test "cj::sandbox::resolve_home respects both overrides" {
    local parent="$TEST_TMPDIR/parent"
    mkdir -p "$parent"

    run cj::sandbox::resolve_home "$parent" ".custom-name"
    assert_success
    assert_output "$parent/.custom-name"
}

@test "cj::sandbox::resolve_home uses config sandbox_name when sandbox_home is absolute" {
    cd "$TEST_TMPDIR"
    # Set sandbox_home to absolute path (new behavior)
    _CJ_CONFIG[sandbox_home]="$TEST_TMPDIR"
    _CJ_CONFIG[sandbox_name]=".config-sandbox"

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$TEST_TMPDIR/.config-sandbox"
}

@test "cj::sandbox::resolve_home treats relative sandbox_home as name (backward compat)" {
    cd "$TEST_TMPDIR"
    # Old behavior: sandbox_home was the directory name, not parent
    _CJ_CONFIG[sandbox_home]=".old-style-sandbox"
    _CJ_CONFIG[sandbox_name]=".new-style-sandbox"

    run cj::sandbox::resolve_home
    assert_success
    # Should use the old sandbox_home value as the name (backward compatibility)
    assert_output "$TEST_TMPDIR/.old-style-sandbox"
}

@test "cj::sandbox::resolve_home uses absolute sandbox_home as parent" {
    local custom_parent="$TEST_TMPDIR/custom-parent"
    mkdir -p "$custom_parent"
    _CJ_CONFIG[sandbox_home]="$custom_parent"
    _CJ_CONFIG[sandbox_name]=".my-sandbox"

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$custom_parent/.my-sandbox"
}

# =============================================================================
# cj::sandbox::validate_home_location tests
# =============================================================================

@test "cj::sandbox::validate_home_location accepts valid path" {
    run cj::sandbox::validate_home_location "$TEST_TMPDIR/.claude-sandbox"
    assert_success
}

@test "cj::sandbox::validate_home_location rejects root" {
    run cj::sandbox::validate_home_location "/"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects /etc" {
    run cj::sandbox::validate_home_location "/etc"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects /home" {
    run cj::sandbox::validate_home_location "/home"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects /usr" {
    run cj::sandbox::validate_home_location "/usr"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects /tmp" {
    run cj::sandbox::validate_home_location "/tmp"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects /var" {
    run cj::sandbox::validate_home_location "/var"
    assert_failure
    assert_output --partial "system directory"
}

@test "cj::sandbox::validate_home_location rejects empty path" {
    run cj::sandbox::validate_home_location ""
    assert_failure
    assert_output --partial "cannot be empty"
}

@test "cj::sandbox::validate_home_location accepts subdirectory of /tmp" {
    run cj::sandbox::validate_home_location "/tmp/my-sandbox"
    assert_success
}

@test "cj::sandbox::validate_home_location accepts subdirectory of /home" {
    run cj::sandbox::validate_home_location "/home/user/project/.sandbox"
    assert_success
}

@test "cj::sandbox::validate_home_location warns for user-level config" {
    run cj::sandbox::validate_home_location "$TEST_TMPDIR/.sandbox" "user"
    assert_success
    assert_output --partial "Warning"
    assert_output --partial "user-level config"
}

@test "cj::sandbox::validate_home_location no warning for project config" {
    run cj::sandbox::validate_home_location "$TEST_TMPDIR/.sandbox" "project"
    assert_success
    refute_output --partial "Warning"
}

@test "cj::sandbox::validate_home_location no warning without source" {
    run cj::sandbox::validate_home_location "$TEST_TMPDIR/.sandbox"
    assert_success
    refute_output --partial "Warning"
}

# =============================================================================
# Integration with config tests
# =============================================================================

@test "sandbox resolution works with CJ_SANDBOX_HOME env var" {
    local custom_parent="$TEST_TMPDIR/env-parent"
    mkdir -p "$custom_parent"
    export CJ_SANDBOX_HOME="$custom_parent"
    cj::config::init

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$custom_parent/.claude-sandbox"
}

@test "sandbox resolution works with CJ_SANDBOX_NAME env var" {
    cd "$TEST_TMPDIR"
    # Need to set sandbox_home to absolute path for sandbox_name to take effect
    export CJ_SANDBOX_HOME="$TEST_TMPDIR"
    export CJ_SANDBOX_NAME=".env-sandbox"
    cj::config::init

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$TEST_TMPDIR/.env-sandbox"
}

@test "sandbox resolution works with both env vars" {
    local custom_parent="$TEST_TMPDIR/env-parent"
    mkdir -p "$custom_parent"
    export CJ_SANDBOX_HOME="$custom_parent"
    export CJ_SANDBOX_NAME=".env-sandbox"
    cj::config::init

    run cj::sandbox::resolve_home
    assert_success
    assert_output "$custom_parent/.env-sandbox"
}

# =============================================================================
# cj::config::is_user_level_config tests
# =============================================================================

@test "cj::config::is_user_level_config returns false when no config loaded" {
    _CJ_CONFIG_SOURCE=""

    if cj::config::is_user_level_config; then
        fail "Expected non-user-level config"
    fi
}

@test "cj::config::is_user_level_config returns true for user config path" {
    _CJ_CONFIG_SOURCE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-jail/config"

    if cj::config::is_user_level_config; then
        true  # Expected
    else
        fail "Expected user-level config detection"
    fi
}

@test "cj::config::is_user_level_config returns true for home config path" {
    _CJ_CONFIG_SOURCE="$HOME/.claude-jail.conf"

    if cj::config::is_user_level_config; then
        true  # Expected
    else
        fail "Expected user-level config detection"
    fi
}

@test "cj::config::is_user_level_config returns false for project config" {
    _CJ_CONFIG_SOURCE="./.claude-jail.conf"

    if cj::config::is_user_level_config; then
        fail "Expected non-user-level config for project config"
    fi
}
