#!/usr/bin/env bash
# tests/test_helper/common.bash - Shared test utilities and setup

# Determine the project root directory
_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_TEST_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$_TEST_ROOT"

# Load bats helpers (use absolute paths)
load "$_TEST_HELPER/bats-support/load"
load "$_TEST_HELPER/bats-assert/load"

# Source the library files (without running any initialization)
source_libs() {
    source "$PROJECT_ROOT/lib/bwrap.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/profiles.sh"
    source "$PROJECT_ROOT/lib/sandbox.sh"
}

# Source only bwrap.sh for isolated unit tests
source_bwrap() {
    source "$PROJECT_ROOT/lib/bwrap.sh"
}

# Source only config.sh for isolated unit tests
source_config() {
    # config.sh depends on declaring the arrays, so we need minimal setup
    source "$PROJECT_ROOT/lib/config.sh"
}

# Source only profiles.sh for isolated unit tests
source_profiles() {
    source "$PROJECT_ROOT/lib/profiles.sh"
}

# Source only sandbox.sh (requires bwrap.sh, config.sh, profiles.sh)
source_sandbox() {
    source "$PROJECT_ROOT/lib/bwrap.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/profiles.sh"
    source "$PROJECT_ROOT/lib/sandbox.sh"
}

# Create a temporary directory for test isolation
setup_test_tmpdir() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
}

# Clean up temporary directory
teardown_test_tmpdir() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Create a mock project directory structure
create_mock_project() {
    local project_dir="${1:-$TEST_TMPDIR/project}"
    mkdir -p "$project_dir"
    echo "$project_dir"
}

# Create a mock sandbox home directory structure
create_mock_sandbox() {
    local sandbox_home="${1:-$TEST_TMPDIR/sandbox}"
    mkdir -p "$sandbox_home"/{.config,.cache,.local/share,.claude}
    echo "$sandbox_home"
}

# Reset all global state (call before each test that modifies globals)
reset_cj_state() {
    cj::reset 2>/dev/null || true
    # Reset config arrays if they exist
    _CJ_EXTRA_RO=() 2>/dev/null || true
    _CJ_EXTRA_RW=() 2>/dev/null || true
    _CJ_BLOCKED=() 2>/dev/null || true
}

# Assert that array contains a specific value
assert_array_contains() {
    local -n arr="$1"
    local expected="$2"
    local found=false

    for item in "${arr[@]}"; do
        if [[ "$item" == "$expected" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != true ]]; then
        echo "Expected array to contain: $expected"
        echo "Array contents: ${arr[*]}"
        return 1
    fi
}

# Assert that array contains a pattern (substring match)
assert_array_contains_pattern() {
    local -n arr="$1"
    local pattern="$2"
    local found=false

    for item in "${arr[@]}"; do
        if [[ "$item" == *"$pattern"* ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != true ]]; then
        echo "Expected array to contain pattern: $pattern"
        echo "Array contents: ${arr[*]}"
        return 1
    fi
}

# Get the bwrap command that would be built (for inspection)
get_bwrap_cmd() {
    local -a cmd=(bwrap --die-with-parent --new-session)
    cmd+=("${_CJ_NS[@]}")
    cmd+=("${_CJ_PRE[@]}")
    cmd+=("${_CJ_BINDS[@]}")
    cmd+=("${_CJ_ENV[@]}")
    echo "${cmd[*]}"
}

# Check if running in CI environment
is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${TRAVIS:-}" ]]
}

# Skip test if not running as root (some bwrap tests need root)
skip_if_not_root() {
    [[ "$(id -u)" != "0" ]] && skip "Test requires root privileges"
}

# Skip test if bwrap is not available
skip_if_no_bwrap() {
    command -v bwrap &>/dev/null || skip "bwrap not installed"
}
