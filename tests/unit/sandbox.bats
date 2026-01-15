#!/usr/bin/env bats
# tests/unit/sandbox.bats - Unit tests for lib/sandbox.sh

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    # Clear environment variables
    unset CJ_PROFILE CJ_NETWORK CJ_SANDBOX_HOME CJ_COPY_CLAUDE_CONFIG
    source_sandbox
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# cj::sandbox::create_dirs tests
# =============================================================================

@test "cj::sandbox::create_dirs creates standard directory structure" {
    local sandbox_home="$TEST_TMPDIR/sandbox"

    cj::sandbox::create_dirs "$sandbox_home"

    assert [ -d "$sandbox_home/.config" ]
    assert [ -d "$sandbox_home/.cache" ]
    assert [ -d "$sandbox_home/.local/share" ]
    assert [ -d "$sandbox_home/.claude" ]
}

@test "cj::sandbox::create_dirs returns error for empty path" {
    run cj::sandbox::create_dirs ""
    assert_failure
}

@test "cj::sandbox::create_dirs is idempotent" {
    local sandbox_home="$TEST_TMPDIR/sandbox"

    cj::sandbox::create_dirs "$sandbox_home"
    # Create a file to verify directory isn't recreated
    touch "$sandbox_home/.config/marker"

    cj::sandbox::create_dirs "$sandbox_home"

    assert [ -f "$sandbox_home/.config/marker" ]
}

# =============================================================================
# cj::sandbox::copy_claude_config tests
# =============================================================================

@test "cj::sandbox::copy_claude_config copies ~/.claude directory" {
    # Skip if rsync not available (used by copy function)
    command -v rsync &>/dev/null || skip "rsync not installed"

    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    echo "test config" > "$HOME/.claude/settings.json"

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"

    # Ensure copy is enabled
    _CJ_CONFIG[copy_claude_config]="true"

    cj::sandbox::copy_claude_config "$sandbox_home"

    assert [ -f "$sandbox_home/.claude/settings.json" ]
    assert [ -f "$sandbox_home/.claude/.copied" ]

    export HOME="$original_home"
}

@test "cj::sandbox::copy_claude_config copies ~/.claude.json" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME"
    echo '{"key": "value"}' > "$HOME/.claude.json"

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home"

    _CJ_CONFIG[copy_claude_config]="true"

    cj::sandbox::copy_claude_config "$sandbox_home"

    assert [ -f "$sandbox_home/.claude.json" ]

    export HOME="$original_home"
}

@test "cj::sandbox::copy_claude_config respects copy_claude_config=false" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    echo "test config" > "$HOME/.claude/settings.json"

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"

    _CJ_CONFIG[copy_claude_config]="false"

    cj::sandbox::copy_claude_config "$sandbox_home"

    # Should NOT have copied
    assert [ ! -f "$sandbox_home/.claude/settings.json" ]

    export HOME="$original_home"
}

@test "cj::sandbox::copy_claude_config skips if already copied" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    echo "original" > "$HOME/.claude/settings.json"

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"
    touch "$sandbox_home/.claude/.copied"
    echo "existing" > "$sandbox_home/.claude/settings.json"

    _CJ_CONFIG[copy_claude_config]="true"

    cj::sandbox::copy_claude_config "$sandbox_home"

    # Should NOT have overwritten existing file
    run cat "$sandbox_home/.claude/settings.json"
    assert_output "existing"

    export HOME="$original_home"
}

# =============================================================================
# cj::sandbox::bind_credentials tests
# =============================================================================

@test "cj::sandbox::bind_credentials binds credentials file" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    touch "$HOME/.claude/.credentials.json"
    unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"

    cj::reset
    # Don't use 'run' here - it runs in subshell and loses array modifications
    cj::sandbox::bind_credentials "$sandbox_home" "standard"
    local status=$?
    assert_equal "$status" 0

    # Should have added bind
    assert_array_contains _CJ_BINDS "$HOME/.claude/.credentials.json"

    export HOME="$original_home"
}

@test "cj::sandbox::bind_credentials uses /sandbox path for paranoid profile" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    touch "$HOME/.claude/.credentials.json"
    unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"

    cj::reset
    cj::sandbox::bind_credentials "$sandbox_home" "paranoid"

    # Should bind to /sandbox/.claude/.credentials.json
    assert_array_contains _CJ_BINDS "/sandbox/.claude/.credentials.json"

    export HOME="$original_home"
}

@test "cj::sandbox::bind_credentials returns failure when no credentials exist" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/empty_home"
    mkdir -p "$HOME"
    unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME

    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$sandbox_home/.claude"

    cj::reset
    run cj::sandbox::bind_credentials "$sandbox_home" "standard"
    assert_failure

    export HOME="$original_home"
}

# =============================================================================
# cj::sandbox::chdir_path tests
# =============================================================================

@test "cj::sandbox::chdir_path returns project_dir for standard profile" {
    run cj::sandbox::chdir_path "/my/project" "standard"
    assert_success
    assert_output "/my/project"
}

@test "cj::sandbox::chdir_path returns /work for paranoid profile" {
    run cj::sandbox::chdir_path "/my/project" "paranoid"
    assert_success
    assert_output "/work"
}

@test "cj::sandbox::chdir_path defaults to standard profile" {
    run cj::sandbox::chdir_path "/my/project"
    assert_success
    assert_output "/my/project"
}

# =============================================================================
# cj::sandbox::home_path tests
# =============================================================================

@test "cj::sandbox::home_path returns sandbox_home for standard profile" {
    run cj::sandbox::home_path "/path/to/.claude-sandbox" "standard"
    assert_success
    assert_output "/path/to/.claude-sandbox"
}

@test "cj::sandbox::home_path returns /sandbox for paranoid profile" {
    run cj::sandbox::home_path "/path/to/.claude-sandbox" "paranoid"
    assert_success
    assert_output "/sandbox"
}

# =============================================================================
# cj::sandbox::init tests
# =============================================================================

@test "cj::sandbox::init creates directories and resets state" {
    local project_dir="$TEST_TMPDIR/project"
    local sandbox_home="$TEST_TMPDIR/sandbox"
    mkdir -p "$project_dir"

    # Add some state that should be reset
    _CJ_NS+=(--unshare-user)

    # Need a mock profile for this test
    _CJ_PROFILES[testprofile]="_mock_profile"
    _mock_profile() {
        cj::setenv HOME "$2"
    }

    cj::sandbox::init "$project_dir" "$sandbox_home" "testprofile"

    # Directories should be created
    assert [ -d "$sandbox_home/.config" ]
    assert [ -d "$sandbox_home/.claude" ]
}

# =============================================================================
# cj::sandbox::print_info tests
# =============================================================================

@test "cj::sandbox::print_info outputs sandbox information" {
    run cj::sandbox::print_info "/project" "/sandbox" "standard" "/usr/bin/claude"

    assert_success
    assert_output --partial "Profile: standard"
    assert_output --partial "Project: /project"
    assert_output --partial "Sandbox: /sandbox"
    assert_output --partial "Claude:"
}

@test "cj::sandbox::print_info works without claude_bin" {
    run cj::sandbox::print_info "/project" "/sandbox" "standard"

    assert_success
    assert_output --partial "Profile: standard"
}

# =============================================================================
# cj::sandbox::print_shell_info tests
# =============================================================================

@test "cj::sandbox::print_shell_info outputs shell entry information" {
    run cj::sandbox::print_shell_info "/sandbox" "standard"

    assert_success
    assert_output --partial "sandbox shell"
    assert_output --partial "HOME"
    assert_output --partial "ls /home"
}

@test "cj::sandbox::print_shell_info shows /sandbox for paranoid profile" {
    run cj::sandbox::print_shell_info "/actual/sandbox" "paranoid"

    assert_success
    assert_output --partial "/sandbox"
}
