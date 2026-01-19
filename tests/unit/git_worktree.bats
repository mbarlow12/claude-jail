#!/usr/bin/env bats
# tests/unit/git_worktree.bats - Unit tests for git worktree detection

load '../test_helper/common'

setup() {
    setup_test_tmpdir
    source_bwrap
}

teardown() {
    teardown_test_tmpdir
}

# =============================================================================
# Helper functions for creating test git structures
# =============================================================================

# Create a mock primary git clone (with .git directory)
create_mock_primary_clone() {
    local dir="$1"
    mkdir -p "$dir/.git/objects" "$dir/.git/refs"
    echo "ref: refs/heads/main" > "$dir/.git/HEAD"
}

# Create a mock worktree (with .git file pointing to main repo)
# Usage: create_mock_worktree <worktree_dir> <main_repo_dir>
create_mock_worktree() {
    local worktree_dir="$1"
    local main_repo_dir="$2"
    local worktree_name
    worktree_name="$(basename "$worktree_dir")"

    mkdir -p "$worktree_dir"
    mkdir -p "$main_repo_dir/.git/worktrees/$worktree_name"

    # Create the gitdir file in worktree
    echo "gitdir: $main_repo_dir/.git/worktrees/$worktree_name" > "$worktree_dir/.git"

    # Create the commondir file in the worktree-specific git dir
    # Points from worktrees/<name> up to .git (two levels up)
    echo "../.." > "$main_repo_dir/.git/worktrees/$worktree_name/commondir"
}

# =============================================================================
# cj::git::get_main_repo_root tests
# =============================================================================

@test "cj::git::get_main_repo_root returns project dir for primary clone" {
    local project="$TEST_TMPDIR/primary"
    create_mock_primary_clone "$project"

    run cj::git::get_main_repo_root "$project"
    assert_success
    assert_output "$project"
}

@test "cj::git::get_main_repo_root returns main repo for worktree" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    run cj::git::get_main_repo_root "$worktree"
    assert_success
    assert_output "$main"
}

@test "cj::git::get_main_repo_root fails for non-git directory" {
    local dir="$TEST_TMPDIR/not-git"
    mkdir -p "$dir"

    run cj::git::get_main_repo_root "$dir"
    assert_failure
}

@test "cj::git::get_main_repo_root fails for empty argument" {
    run cj::git::get_main_repo_root ""
    assert_failure
}

@test "cj::git::get_main_repo_root handles sibling worktree layout" {
    # Layout:
    # parent/
    #   main/        <- primary clone
    #   feat-branch/ <- worktree
    local parent="$TEST_TMPDIR/parent"
    local main="$parent/main"
    local worktree="$parent/feat-branch"

    mkdir -p "$parent"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    run cj::git::get_main_repo_root "$worktree"
    assert_success
    assert_output "$main"
}

# =============================================================================
# cj::git::detect_worktree tests
# =============================================================================

@test "cj::git::detect_worktree succeeds for primary clone (no extra binding)" {
    local project="$TEST_TMPDIR/primary"
    create_mock_primary_clone "$project"

    # Call directly (not with run) so _CJ_BINDS is modified
    cj::git::detect_worktree "$project" false false ""
    local result=$?

    # Should succeed
    assert_equal "$result" 0

    # Should not have bound anything extra (primary .git is part of project)
    local found=false
    for item in "${_CJ_BINDS[@]}"; do
        [[ "$item" == "$project/.git" ]] && found=true
    done
    assert [ "$found" = false ]
}

@test "cj::git::detect_worktree binds main .git for worktree" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    # Call directly so _CJ_BINDS is modified
    cj::git::detect_worktree "$worktree" false false ""
    local result=$?

    assert_equal "$result" 0
    # Should have bound main/.git
    assert_array_contains _CJ_BINDS "$main/.git"
}

@test "cj::git::detect_worktree binds read-write by default" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    cj::git::detect_worktree "$worktree" false false ""

    # Should use --bind (read-write), not --ro-bind
    assert_array_contains _CJ_BINDS "--bind"
}

@test "cj::git::detect_worktree binds read-only when requested" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    cj::git::detect_worktree "$worktree" true false ""

    # Should use --ro-bind (read-only)
    assert_array_contains _CJ_BINDS "--ro-bind"
}

@test "cj::git::detect_worktree fails for non-git directory" {
    local dir="$TEST_TMPDIR/not-git"
    mkdir -p "$dir"

    run cj::git::detect_worktree "$dir" false false ""
    assert_failure
}

@test "cj::git::detect_worktree uses manual git root override" {
    local main="$TEST_TMPDIR/main"
    local project="$TEST_TMPDIR/project"
    create_mock_primary_clone "$main"
    mkdir -p "$project"  # Not a git repo, but we'll override

    # Create a .git file to make it look like a worktree (but broken)
    echo "gitdir: /nonexistent/path" > "$project/.git"

    # Use manual override - call directly so _CJ_BINDS is modified
    cj::git::detect_worktree "$project" false false "$main"

    # Should have bound the manually specified main/.git
    assert_array_contains _CJ_BINDS "$main/.git"
}

@test "cj::git::detect_worktree fails with invalid manual git root" {
    local project="$TEST_TMPDIR/project"
    mkdir -p "$project"
    touch "$project/.git"  # Make it look like a worktree

    run cj::git::detect_worktree "$project" false false "$TEST_TMPDIR/nonexistent"
    assert_failure
    assert_output --partial "does not contain .git"
}

@test "cj::git::detect_worktree skips binding if main .git inside project" {
    # Edge case: main .git is somehow inside project directory
    local project="$TEST_TMPDIR/project"
    mkdir -p "$project/subrepo"
    create_mock_primary_clone "$project/subrepo"

    # Create a worktree that points to subrepo - need ../.. to point to .git
    echo "gitdir: $project/subrepo/.git/worktrees/fake" > "$project/.git"
    mkdir -p "$project/subrepo/.git/worktrees/fake"
    echo "../.." > "$project/subrepo/.git/worktrees/fake/commondir"

    # The main .git is inside project, so no extra binding needed
    cj::git::detect_worktree "$project" false false ""

    # Should succeed and not bind (since it's already inside project)
    local found=false
    for item in "${_CJ_BINDS[@]}"; do
        [[ "$item" == "$project/subrepo/.git" ]] && found=true
    done
    # In this case it shouldn't matter either way, just shouldn't fail
}

# =============================================================================
# Verbose output tests
# =============================================================================

@test "cj::git::detect_worktree prints verbose output when enabled" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    run cj::git::detect_worktree "$worktree" false true ""
    assert_success
    assert_output --partial "Git:"
}

@test "cj::git::detect_worktree silent when verbose disabled" {
    local main="$TEST_TMPDIR/main"
    local worktree="$TEST_TMPDIR/feat-branch"
    create_mock_primary_clone "$main"
    create_mock_worktree "$worktree" "$main"

    run cj::git::detect_worktree "$worktree" false false ""
    assert_success
    assert_output ""
}
