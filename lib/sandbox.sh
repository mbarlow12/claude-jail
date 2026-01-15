#!/usr/bin/env bash
# lib/sandbox.sh - Sandbox setup and management utilities (pure bash)
# Provides shared functionality for sandbox initialization and configuration

# Create standard sandbox directory structure
# Usage: cj::sandbox::create_dirs <sandbox_home>
cj::sandbox::create_dirs() {
    local sandbox_home="$1"
    [[ -z "$sandbox_home" ]] && return 1
    mkdir -p "$sandbox_home"/{.config,.cache,.local/share,.claude}
}

# Copy Claude configuration from host to sandbox (if enabled and not already copied)
# Usage: cj::sandbox::copy_claude_config <sandbox_home>
cj::sandbox::copy_claude_config() {
    local sandbox_home="$1"
    [[ -z "$sandbox_home" ]] && return 1

    if ! cj::config::get_bool copy_claude_config true; then
        return 0
    fi

    # Copy ~/.claude directory if it exists and hasn't been copied
    if [[ -d ~/.claude ]] && [[ ! -f "$sandbox_home/.claude/.copied" ]]; then
        rsync -a --ignore-existing ~/.claude/ "$sandbox_home/.claude/" 2>/dev/null || true
        touch "$sandbox_home/.claude/.copied"
    fi

    # Copy ~/.claude.json if it exists and hasn't been copied
    if [[ -f ~/.claude.json ]] && [[ ! -f "$sandbox_home/.claude.json" ]]; then
        cp ~/.claude.json "$sandbox_home/.claude.json" 2>/dev/null || true
    fi
}

# Bind credentials file for live sync (allows /login to persist)
# Usage: cj::sandbox::bind_credentials <sandbox_home> <profile>
cj::sandbox::bind_credentials() {
    local sandbox_home="$1"
    local profile="${2:-standard}"
    local cred_source cred_target

    if cred_source="$(cj::credentials::find)"; then
        cred_target="$sandbox_home/.claude/.credentials.json"
        [[ "$profile" == "paranoid" ]] && cred_target="/sandbox/.claude/.credentials.json"
        touch "$sandbox_home/.claude/.credentials.json"
        cj::bind "$cred_source" "$cred_target"
        return 0
    fi
    return 1
}

# Get the working directory path based on profile
# Usage: cj::sandbox::chdir_path <project_dir> <profile>
cj::sandbox::chdir_path() {
    local project_dir="$1"
    local profile="${2:-standard}"

    if [[ "$profile" == "paranoid" ]]; then
        echo "/work"
    else
        echo "$project_dir"
    fi
}

# Get the sandbox home path based on profile (for display purposes)
# Usage: cj::sandbox::home_path <sandbox_home> <profile>
cj::sandbox::home_path() {
    local sandbox_home="$1"
    local profile="${2:-standard}"

    if [[ "$profile" == "paranoid" ]]; then
        echo "/sandbox"
    else
        echo "$sandbox_home"
    fi
}

# Full sandbox initialization: create dirs, copy config, reset state, apply profile
# Usage: cj::sandbox::init <project_dir> <sandbox_home> <profile>
cj::sandbox::init() {
    local project_dir="$1"
    local sandbox_home="$2"
    local profile="${3:-standard}"

    cj::sandbox::create_dirs "$sandbox_home"
    cj::sandbox::copy_claude_config "$sandbox_home"
    cj::reset
    cj::profile::apply "$profile" "$project_dir" "$sandbox_home"
}

# Print verbose startup information
# Usage: cj::sandbox::print_info <project_dir> <sandbox_home> <profile> <claude_bin>
cj::sandbox::print_info() {
    local project_dir="$1"
    local sandbox_home="$2"
    local profile="$3"
    local claude_bin="${4:-claude}"

    echo "claude-jail"
    echo "   Profile: $profile"
    echo "   Project: $project_dir"
    echo "   Sandbox: $sandbox_home"
    [[ -n "$claude_bin" ]] && echo "   Claude:  $claude_bin"
    echo ""
}

# Print shell entry information
# Usage: cj::sandbox::print_shell_info <sandbox_home> <profile>
cj::sandbox::print_shell_info() {
    local sandbox_home="$1"
    local profile="${2:-standard}"
    local display_home

    display_home="$(cj::sandbox::home_path "$sandbox_home" "$profile")"
    echo "Entering sandbox shell (profile: $profile)"
    echo "   \$HOME = $display_home"
    echo "   Try: ls /home  (should fail)"
    echo ""
}
