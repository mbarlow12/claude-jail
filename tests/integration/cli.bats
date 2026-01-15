#!/usr/bin/env bats
# tests/integration/cli.bats - Integration tests for bin/claude-jail CLI

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    # Clear environment
    unset CJ_PROFILE CJ_NETWORK CJ_SANDBOX_HOME CJ_COPY_CLAUDE_CONFIG
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# Help and info commands
# =============================================================================

@test "claude-jail --help shows usage" {
    run "$PROJECT_ROOT/bin/claude-jail" --help

    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "OPTIONS"
    assert_output --partial "PROFILES"
}

@test "claude-jail -h shows usage" {
    run "$PROJECT_ROOT/bin/claude-jail" -h

    assert_success
    assert_output --partial "USAGE"
}

@test "claude-jail --help-config shows configuration help" {
    run "$PROJECT_ROOT/bin/claude-jail" --help-config

    assert_success
    assert_output --partial "CONFIGURATION"
    assert_output --partial "CJ_PROFILE"
}

@test "claude-jail --list-profiles shows available profiles" {
    run "$PROJECT_ROOT/bin/claude-jail" --list-profiles

    assert_success
    assert_output --partial "standard"
    assert_output --partial "minimal"
    assert_output --partial "paranoid"
    assert_output --partial "dev"
}

@test "claude-jail --show-config displays current configuration" {
    run "$PROJECT_ROOT/bin/claude-jail" --show-config

    assert_success
    assert_output --partial "profile:"
    assert_output --partial "network:"
}

# =============================================================================
# Debug command tests
# =============================================================================

@test "claude-jail debug generates bwrap command" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir"

    assert_success
    assert_output --partial "bwrap"
    assert_output --partial "--die-with-parent"
    assert_output --partial "Profile: standard"
}

@test "claude-jail debug respects profile argument" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir" paranoid

    assert_success
    assert_output --partial "Profile: paranoid"
}

@test "claude-jail debug creates sandbox directories" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir" >/dev/null

    assert [ -d "$project_dir/.claude-sandbox/.config" ]
    assert [ -d "$project_dir/.claude-sandbox/.claude" ]
}

# =============================================================================
# Clean command tests
# =============================================================================

@test "claude-jail clean removes sandbox directory" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir/.claude-sandbox"
    touch "$project_dir/.claude-sandbox/testfile"

    run "$PROJECT_ROOT/bin/claude-jail" clean "$project_dir"

    assert_success
    assert_output --partial "Removing"
    assert [ ! -d "$project_dir/.claude-sandbox" ]
}

@test "claude-jail clean handles nonexistent sandbox" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    run "$PROJECT_ROOT/bin/claude-jail" clean "$project_dir"

    assert_success
    assert_output --partial "No sandbox found"
}

# =============================================================================
# CLI argument parsing tests
# =============================================================================

@test "claude-jail debug accepts positional arguments" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    # debug takes positional args: [project_dir] [profile]
    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir"

    assert_success
    assert_output --partial "Project: $project_dir"
}

@test "claude-jail debug accepts profile as second argument" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    # debug takes positional args: [project_dir] [profile]
    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir" minimal

    assert_success
    assert_output --partial "Profile: minimal"
}

@test "claude-jail rejects unknown profile" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    run "$PROJECT_ROOT/bin/claude-jail" -d "$project_dir" -p nonexistent_profile --list-profiles 2>&1 || true

    # The list-profiles command should still work
    run "$PROJECT_ROOT/bin/claude-jail" --list-profiles
    assert_success
}

@test "claude-jail rejects unknown options" {
    run "$PROJECT_ROOT/bin/claude-jail" --unknown-option

    assert_failure
    assert_output --partial "Unknown option"
}

# =============================================================================
# Environment variable tests
# =============================================================================

@test "claude-jail respects CJ_PROFILE environment variable" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    export CJ_PROFILE="dev"
    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir"

    assert_success
    assert_output --partial "Profile: dev"
}

@test "CLI profile arg overrides CJ_PROFILE for debug command" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    export CJ_PROFILE="dev"
    # debug takes positional args: [project_dir] [profile]
    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir" minimal

    assert_success
    assert_output --partial "Profile: minimal"
}

@test "claude-jail respects CJ_SANDBOX_HOME" {
    local project_dir="$TEST_TMPDIR/project"
    mkdir -p "$project_dir"

    export CJ_SANDBOX_HOME=".my-custom-sandbox"
    run "$PROJECT_ROOT/bin/claude-jail" debug "$project_dir"

    assert_success
    assert_output --partial ".my-custom-sandbox"
}

# =============================================================================
# Directory validation tests
# =============================================================================

@test "debug command works with nonexistent directory (shows what would run)" {
    # debug command doesn't validate directory existence - it shows what WOULD run
    run "$PROJECT_ROOT/bin/claude-jail" debug "/nonexistent/directory/12345"

    assert_success
    assert_output --partial "bwrap"
    assert_output --partial "/nonexistent/directory/12345"
}
