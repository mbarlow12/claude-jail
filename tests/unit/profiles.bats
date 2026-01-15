#!/usr/bin/env bats
# tests/unit/profiles.bats - Unit tests for lib/profiles.sh

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    source_profiles
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# cj::profile::register tests
# =============================================================================

@test "cj::profile::register adds profile to registry" {
    _CJ_PROFILES=()

    _test_profile_fn() {
        echo "test profile"
    }

    cj::profile::register "testprofile" "_test_profile_fn"

    assert_equal "${_CJ_PROFILES[testprofile]}" "_test_profile_fn"
}

@test "cj::profile::register overwrites existing profile" {
    _old_fn() { echo "old"; }
    _new_fn() { echo "new"; }

    cj::profile::register "myprofile" "_old_fn"
    cj::profile::register "myprofile" "_new_fn"

    assert_equal "${_CJ_PROFILES[myprofile]}" "_new_fn"
}

# =============================================================================
# cj::profile::list tests
# =============================================================================

@test "cj::profile::list returns registered profiles" {
    _CJ_PROFILES=()
    cj::profile::register "alpha" "_fn"
    cj::profile::register "beta" "_fn"
    cj::profile::register "gamma" "_fn"

    run cj::profile::list

    assert_success
    assert_output --partial "alpha"
    assert_output --partial "beta"
    assert_output --partial "gamma"
}

@test "cj::profile::list returns sorted output" {
    _CJ_PROFILES=()
    cj::profile::register "zebra" "_fn"
    cj::profile::register "apple" "_fn"
    cj::profile::register "mango" "_fn"

    run cj::profile::list

    # First line should be apple (sorted)
    local first_line
    first_line=$(echo "$output" | head -1)
    assert_equal "$first_line" "apple"
}

# =============================================================================
# cj::profile::exists tests
# =============================================================================

@test "cj::profile::exists returns success for registered profile" {
    _CJ_PROFILES=()
    cj::profile::register "existing" "_fn"

    run cj::profile::exists "existing"
    assert_success
}

@test "cj::profile::exists returns failure for unregistered profile" {
    _CJ_PROFILES=()

    run cj::profile::exists "nonexistent"
    assert_failure
}

# =============================================================================
# cj::profile::apply tests
# =============================================================================

@test "cj::profile::apply calls the profile function" {
    _CJ_PROFILES=()
    _test_apply_fn() {
        echo "applied:$1:$2"
    }
    cj::profile::register "testapply" "_test_apply_fn"

    run cj::profile::apply "testapply" "/project" "/sandbox"

    assert_success
    assert_output "applied:/project:/sandbox"
}

@test "cj::profile::apply fails for unknown profile" {
    _CJ_PROFILES=()

    run cj::profile::apply "unknown" "/project" "/sandbox"

    assert_failure
    assert_output --partial "Unknown profile"
}

@test "cj::profile::apply shows available profiles on error" {
    _CJ_PROFILES=()
    cj::profile::register "available1" "_fn"
    cj::profile::register "available2" "_fn"

    run cj::profile::apply "unknown" "/project" "/sandbox"

    assert_failure
    assert_output --partial "Available:"
}

# =============================================================================
# cj::profile::load_all tests
# =============================================================================

@test "cj::profile::load_all loads profiles from directory" {
    _CJ_PROFILES=()
    local profile_dir="$TEST_TMPDIR/profiles"
    mkdir -p "$profile_dir"

    # Create a test profile file
    cat > "$profile_dir/test.sh" <<'EOF'
_cj_profile_loadtest() {
    echo "loadtest"
}
cj::profile::register loadtest _cj_profile_loadtest
EOF

    cj::profile::load_all "$profile_dir"

    assert [ -n "${_CJ_PROFILES[loadtest]:-}" ]
}

@test "cj::profile::load_all handles empty directory" {
    local profile_dir="$TEST_TMPDIR/empty_profiles"
    mkdir -p "$profile_dir"

    run cj::profile::load_all "$profile_dir"
    assert_success
}

@test "cj::profile::load_all handles nonexistent directory" {
    run cj::profile::load_all "/nonexistent/dir"
    assert_success
}

@test "cj::profile::load_all loads multiple profiles" {
    _CJ_PROFILES=()
    local profile_dir="$TEST_TMPDIR/profiles"
    mkdir -p "$profile_dir"

    cat > "$profile_dir/one.sh" <<'EOF'
cj::profile::register one "_fn"
EOF

    cat > "$profile_dir/two.sh" <<'EOF'
cj::profile::register two "_fn"
EOF

    cj::profile::load_all "$profile_dir"

    assert [ -n "${_CJ_PROFILES[one]:-}" ]
    assert [ -n "${_CJ_PROFILES[two]:-}" ]
}
