#!/usr/bin/env bats
# tests/integration/profiles.bats - Integration tests for profiles

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    source_libs
    cj::profile::load_all "$PROJECT_ROOT/profiles"
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# Profile loading tests
# =============================================================================

@test "all default profiles are loaded" {
    run cj::profile::list

    assert_success
    assert_output --partial "minimal"
    assert_output --partial "standard"
    assert_output --partial "paranoid"
    assert_output --partial "dev"
}

# =============================================================================
# Standard profile tests
# =============================================================================

@test "standard profile sets HOME environment" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    assert_array_contains _CJ_ENV "HOME"
    assert_array_contains _CJ_ENV "$sandbox"
}

@test "standard profile binds project directory" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    assert_array_contains _CJ_BINDS "$project"
}

@test "standard profile unshares namespaces" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    assert_array_contains _CJ_NS "--unshare-user"
    assert_array_contains _CJ_NS "--unshare-pid"
}

@test "standard profile mounts /proc and /dev" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    assert_array_contains _CJ_BINDS "--proc"
    assert_array_contains _CJ_BINDS "--dev"
}

@test "standard profile sets XDG variables" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    assert_array_contains _CJ_ENV "XDG_CONFIG_HOME"
    assert_array_contains _CJ_ENV "XDG_DATA_HOME"
    assert_array_contains _CJ_ENV "XDG_CACHE_HOME"
}

# =============================================================================
# Minimal profile tests
# =============================================================================

@test "minimal profile unshares all namespaces" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "minimal" "$project" "$sandbox"

    assert_array_contains _CJ_NS "--unshare-all"
}

@test "minimal profile shares network" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "minimal" "$project" "$sandbox"

    assert_array_contains _CJ_NS "--share-net"
}

# =============================================================================
# Paranoid profile tests
# =============================================================================

@test "paranoid profile remaps project to /work" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "paranoid" "$project" "$sandbox"

    # Should bind project to /work
    local found=false
    for ((i=0; i<${#_CJ_BINDS[@]}-1; i++)); do
        if [[ "${_CJ_BINDS[$i]}" == "--bind" && "${_CJ_BINDS[$((i+2))]}" == "/work" ]]; then
            found=true
            break
        fi
    done
    assert [ "$found" = true ]
}

@test "paranoid profile remaps sandbox to /sandbox" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "paranoid" "$project" "$sandbox"

    # Should bind sandbox to /sandbox
    local found=false
    for ((i=0; i<${#_CJ_BINDS[@]}-1; i++)); do
        if [[ "${_CJ_BINDS[$i]}" == "--bind" && "${_CJ_BINDS[$((i+2))]}" == "/sandbox" ]]; then
            found=true
            break
        fi
    done
    assert [ "$found" = true ]
}

@test "paranoid profile sets HOME to /sandbox" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "paranoid" "$project" "$sandbox"

    assert_array_contains _CJ_ENV "/sandbox"
}

@test "paranoid profile sets minimal PATH" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "paranoid" "$project" "$sandbox"

    # Should have restricted PATH
    assert_array_contains _CJ_ENV "/usr/local/bin:/usr/bin:/bin"
}

# =============================================================================
# Dev profile tests
# =============================================================================

@test "dev profile inherits from standard" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "dev" "$project" "$sandbox"

    # Should have standard profile features
    assert_array_contains _CJ_NS "--unshare-user"
    assert_array_contains _CJ_ENV "HOME"
}

@test "dev profile binds mise if available" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    # Create fake mise directory
    local original_home="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/share/mise"

    cj::reset
    cj::profile::apply "dev" "$project" "$sandbox"

    # Should bind mise
    assert_array_contains _CJ_BINDS "$HOME/.local/share/mise"

    export HOME="$original_home"
}

# =============================================================================
# Profile bwrap command validity tests
# =============================================================================

@test "standard profile generates valid bwrap arguments" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "standard" "$project" "$sandbox"

    # Build command should not fail
    run cj::build
    assert_success

    # Should contain essential bwrap elements
    assert_output --partial "bwrap"
    assert_output --partial "--die-with-parent"
}

@test "minimal profile generates valid bwrap arguments" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "minimal" "$project" "$sandbox"

    run cj::build
    assert_success
    assert_output --partial "bwrap"
}

@test "paranoid profile generates valid bwrap arguments" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "paranoid" "$project" "$sandbox"

    run cj::build
    assert_success
    assert_output --partial "bwrap"
}

@test "dev profile generates valid bwrap arguments" {
    local project="$TEST_TMPDIR/project"
    local sandbox="$TEST_TMPDIR/sandbox"
    mkdir -p "$project" "$sandbox"

    cj::reset
    cj::profile::apply "dev" "$project" "$sandbox"

    run cj::build
    assert_success
    assert_output --partial "bwrap"
}
