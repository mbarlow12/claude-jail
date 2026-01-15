#!/usr/bin/env bats
# tests/unit/bwrap.bats - Unit tests for lib/bwrap.sh

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    source_bwrap
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# cj::reset tests
# =============================================================================

@test "cj::reset clears all global arrays" {
    # Add some data to the arrays
    _CJ_NS+=(--unshare-user)
    _CJ_PRE+=(--dir /test)
    _CJ_BINDS+=(--bind /src /dst)
    _CJ_ENV+=(--setenv FOO bar)
    _CJ_SEEN[test]=1

    cj::reset

    assert_equal "${#_CJ_NS[@]}" 0
    assert_equal "${#_CJ_PRE[@]}" 0
    assert_equal "${#_CJ_BINDS[@]}" 0
    assert_equal "${#_CJ_ENV[@]}" 0
    assert_equal "${#_CJ_SEEN[@]}" 0
}

# =============================================================================
# cj::ro_bind tests
# =============================================================================

@test "cj::ro_bind adds read-only bind mount" {
    local test_file="$TEST_TMPDIR/testfile"
    touch "$test_file"

    cj::ro_bind "$test_file"

    assert_array_contains _CJ_BINDS "--ro-bind"
    assert_array_contains _CJ_BINDS "$test_file"
}

@test "cj::ro_bind returns error for non-existent path" {
    run cj::ro_bind "/nonexistent/path/that/does/not/exist"
    assert_failure
}

@test "cj::ro_bind supports custom destination" {
    local test_file="$TEST_TMPDIR/testfile"
    touch "$test_file"

    cj::ro_bind "$test_file" "/custom/dest"

    # Check that --ro-bind is in the array
    local found=false
    for ((i=0; i<${#_CJ_BINDS[@]}; i++)); do
        if [[ "${_CJ_BINDS[$i]}" == "--ro-bind" ]]; then
            # Next two elements should be source and dest
            [[ "${_CJ_BINDS[$((i+2))]}" == "/custom/dest" ]] && found=true
            break
        fi
    done
    assert [ "$found" = true ]
}

@test "cj::ro_bind deduplicates same destination" {
    local test_file="$TEST_TMPDIR/testfile"
    touch "$test_file"

    cj::ro_bind "$test_file"
    local count_before=${#_CJ_BINDS[@]}

    cj::ro_bind "$test_file"
    local count_after=${#_CJ_BINDS[@]}

    assert_equal "$count_before" "$count_after"
}

# =============================================================================
# cj::bind tests
# =============================================================================

@test "cj::bind adds read-write bind mount" {
    local test_dir="$TEST_TMPDIR/testdir"
    mkdir -p "$test_dir"

    cj::bind "$test_dir"

    assert_array_contains _CJ_BINDS "--bind"
    assert_array_contains _CJ_BINDS "$test_dir"
}

@test "cj::bind returns error for non-existent path" {
    run cj::bind "/nonexistent/path/that/does/not/exist"
    assert_failure
}

@test "cj::bind deduplicates same destination" {
    local test_dir="$TEST_TMPDIR/testdir"
    mkdir -p "$test_dir"

    cj::bind "$test_dir"
    local count_before=${#_CJ_BINDS[@]}

    cj::bind "$test_dir"
    local count_after=${#_CJ_BINDS[@]}

    assert_equal "$count_before" "$count_after"
}

# =============================================================================
# cj::tmpfs tests
# =============================================================================

@test "cj::tmpfs adds tmpfs mount" {
    cj::tmpfs /tmp

    assert_array_contains _CJ_BINDS "--tmpfs"
    assert_array_contains _CJ_BINDS "/tmp"
}

@test "cj::tmpfs creates parent directories" {
    cj::tmpfs /some/deep/path/tmpfs

    # Should have --dir entries for parent paths
    assert_array_contains _CJ_PRE "--dir"
}

# =============================================================================
# cj::symlink tests
# =============================================================================

@test "cj::symlink adds symlink" {
    cj::symlink usr/bin /bin

    assert_array_contains _CJ_BINDS "--symlink"
    assert_array_contains _CJ_BINDS "usr/bin"
    assert_array_contains _CJ_BINDS "/bin"
}

# =============================================================================
# cj::dev and cj::proc tests
# =============================================================================

@test "cj::dev adds /dev mount" {
    cj::dev

    assert_array_contains _CJ_BINDS "--dev"
    assert_array_contains _CJ_BINDS "/dev"
}

@test "cj::dev supports custom path" {
    cj::dev /custom/dev

    assert_array_contains _CJ_BINDS "/custom/dev"
}

@test "cj::proc adds /proc mount" {
    cj::proc

    assert_array_contains _CJ_BINDS "--proc"
    assert_array_contains _CJ_BINDS "/proc"
}

@test "cj::proc supports custom path" {
    cj::proc /custom/proc

    assert_array_contains _CJ_BINDS "/custom/proc"
}

# =============================================================================
# cj::setenv tests
# =============================================================================

@test "cj::setenv adds environment variable" {
    cj::setenv FOO "bar"

    assert_array_contains _CJ_ENV "--setenv"
    assert_array_contains _CJ_ENV "FOO"
    assert_array_contains _CJ_ENV "bar"
}

@test "cj::setenv handles values with spaces" {
    cj::setenv PATH "/usr/bin:/bin"

    assert_array_contains _CJ_ENV "PATH"
    assert_array_contains _CJ_ENV "/usr/bin:/bin"
}

# =============================================================================
# cj::chdir tests
# =============================================================================

@test "cj::chdir adds chdir argument" {
    cj::chdir /work

    assert_array_contains _CJ_BINDS "--chdir"
    assert_array_contains _CJ_BINDS "/work"
}

# =============================================================================
# cj::unshare and cj::share tests
# =============================================================================

@test "cj::unshare adds namespace flags" {
    cj::unshare user pid net

    assert_array_contains _CJ_NS "--unshare-user"
    assert_array_contains _CJ_NS "--unshare-pid"
    assert_array_contains _CJ_NS "--unshare-net"
}

@test "cj::unshare all adds unshare-all flag" {
    cj::unshare all

    assert_array_contains _CJ_NS "--unshare-all"
}

@test "cj::share net adds share-net flag" {
    cj::share net

    assert_array_contains _CJ_NS "--share-net"
}

# =============================================================================
# cj::system::* tests
# =============================================================================

@test "cj::system::base binds /usr" {
    cj::system::base

    assert_array_contains _CJ_BINDS "/usr"
}

@test "cj::system::dns binds resolv.conf if exists" {
    # Only test if file exists on system
    if [[ -f /etc/resolv.conf ]]; then
        cj::system::dns
        assert_array_contains _CJ_BINDS "/etc/resolv.conf"
    else
        skip "/etc/resolv.conf not found"
    fi
}

@test "cj::system::ssl binds /etc/ssl if exists" {
    if [[ -d /etc/ssl ]]; then
        cj::system::ssl
        assert_array_contains _CJ_BINDS "/etc/ssl"
    else
        skip "/etc/ssl not found"
    fi
}

@test "cj::system::users binds passwd if exists" {
    if [[ -f /etc/passwd ]]; then
        cj::system::users
        assert_array_contains _CJ_BINDS "/etc/passwd"
    else
        skip "/etc/passwd not found"
    fi
}

# =============================================================================
# cj::path::bind_all tests
# =============================================================================

@test "cj::path::bind_all binds directories in PATH" {
    # Use a controlled PATH for testing
    local original_path="$PATH"
    export PATH="/usr/bin:/bin"

    cj::path::bind_all

    assert_array_contains _CJ_BINDS "/usr/bin"
    assert_array_contains _CJ_BINDS "/bin"

    export PATH="$original_path"
}

# =============================================================================
# cj::path::find_real tests
# =============================================================================

@test "cj::path::find_real returns path for existing command" {
    run cj::path::find_real bash
    assert_success
    assert_output --regexp "bash$"
}

@test "cj::path::find_real fails for nonexistent command" {
    run cj::path::find_real nonexistent_command_12345
    assert_failure
}

# =============================================================================
# cj::build tests
# =============================================================================

@test "cj::build returns bwrap command string" {
    cj::unshare user
    cj::setenv HOME /sandbox

    run cj::build

    assert_success
    assert_output --partial "bwrap"
    assert_output --partial "--die-with-parent"
    assert_output --partial "--unshare-user"
    assert_output --partial "--setenv"
}

# =============================================================================
# cj::env::passthrough tests
# =============================================================================

@test "cj::env::passthrough passes GIT_AUTHOR_NAME if set" {
    export GIT_AUTHOR_NAME="Test User"

    cj::env::passthrough

    assert_array_contains _CJ_ENV "GIT_AUTHOR_NAME"
    assert_array_contains _CJ_ENV "Test User"

    unset GIT_AUTHOR_NAME
}

@test "cj::env::passthrough passes ANTHROPIC_API_KEY if set" {
    export ANTHROPIC_API_KEY="test-key"

    cj::env::passthrough

    assert_array_contains _CJ_ENV "ANTHROPIC_API_KEY"
    assert_array_contains _CJ_ENV "test-key"

    unset ANTHROPIC_API_KEY
}

@test "cj::env::passthrough skips unset variables" {
    unset GIT_AUTHOR_NAME 2>/dev/null || true

    cj::env::passthrough

    local found=false
    for item in "${_CJ_ENV[@]}"; do
        [[ "$item" == "GIT_AUTHOR_NAME" ]] && found=true
    done

    assert [ "$found" = false ]
}

# =============================================================================
# cj::credentials::find tests
# =============================================================================

@test "cj::credentials::find returns failure when no credentials exist" {
    # Use empty HOME to ensure no credentials are found
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/empty_home"
    mkdir -p "$HOME"
    unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME 2>/dev/null || true

    run cj::credentials::find
    assert_failure

    export HOME="$original_home"
}

@test "cj::credentials::find finds credentials in ~/.claude" {
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    touch "$HOME/.claude/.credentials.json"
    unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME 2>/dev/null || true

    run cj::credentials::find
    assert_success
    assert_output "$HOME/.claude/.credentials.json"

    export HOME="$original_home"
}

@test "cj::credentials::find respects CLAUDE_CONFIG_DIR" {
    export CLAUDE_CONFIG_DIR="$TEST_TMPDIR/custom_claude"
    mkdir -p "$CLAUDE_CONFIG_DIR"
    touch "$CLAUDE_CONFIG_DIR/.credentials.json"

    run cj::credentials::find
    assert_success
    assert_output "$CLAUDE_CONFIG_DIR/.credentials.json"

    unset CLAUDE_CONFIG_DIR
}

# =============================================================================
# cj::worktree::detect_config tests
# =============================================================================

@test "cj::worktree::detect_config binds parent .claude if child lacks it" {
    local parent="$TEST_TMPDIR/parent"
    local child="$parent/child"
    mkdir -p "$parent/.claude"
    mkdir -p "$child"

    cj::worktree::detect_config "$child" false

    assert_array_contains _CJ_BINDS "$parent/.claude"
}

@test "cj::worktree::detect_config does not bind if child has .claude" {
    local parent="$TEST_TMPDIR/parent"
    local child="$parent/child"
    mkdir -p "$parent/.claude"
    mkdir -p "$child/.claude"

    cj::worktree::detect_config "$child" false

    # Should not have bound parent's .claude
    local found=false
    for item in "${_CJ_BINDS[@]}"; do
        [[ "$item" == "$parent/.claude" ]] && found=true
    done
    assert [ "$found" = false ]
}

@test "cj::worktree::detect_config binds parent CLAUDE.md if child lacks it" {
    local parent="$TEST_TMPDIR/parent"
    local child="$parent/child"
    mkdir -p "$parent"
    mkdir -p "$child"
    touch "$parent/CLAUDE.md"

    cj::worktree::detect_config "$child" false

    assert_array_contains _CJ_BINDS "$parent/CLAUDE.md"
}
