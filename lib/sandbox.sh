#!/usr/bin/env bash
# lib/sandbox.sh - Sandbox setup and management utilities (pure bash)
# Provides shared functionality for sandbox initialization and configuration

# =============================================================================
# Sandbox home resolution and validation
# =============================================================================

# Resolve full sandbox path from configuration
# Uses CJ_SANDBOX_HOME (parent directory) and CJ_SANDBOX_NAME (directory name)
# Usage: cj::sandbox::resolve_home [parent_override] [name_override]
#   parent_override: Optional parent directory (default: cwd)
#   name_override: Optional sandbox name (default: from config or .claude-sandbox)
# Outputs: Full absolute path to sandbox directory
cj::sandbox::resolve_home() {
    local parent_override="${1:-}"
    local name_override="${2:-}"
    local sandbox_parent sandbox_name
    local sandbox_home_config sandbox_name_config

    # Get config values
    sandbox_home_config="$(cj::config::get sandbox_home "")"
    sandbox_name_config="$(cj::config::get sandbox_name ".claude-sandbox")"

    # Determine sandbox parent directory
    if [[ -n "$parent_override" ]]; then
        sandbox_parent="$parent_override"
    elif [[ -n "$sandbox_home_config" && "$sandbox_home_config" == /* ]]; then
        # Absolute path in sandbox_home config - use as parent
        sandbox_parent="$sandbox_home_config"
    else
        # Default to cwd
        sandbox_parent="$(pwd)"
    fi

    # Determine sandbox directory name
    if [[ -n "$name_override" ]]; then
        sandbox_name="$name_override"
    elif [[ -n "$sandbox_home_config" && "$sandbox_home_config" != /* ]]; then
        # Relative path in sandbox_home config (backward compat) - use as name
        sandbox_name="$sandbox_home_config"
    else
        # Use sandbox_name config
        sandbox_name="$sandbox_name_config"
    fi

    # Resolve parent to absolute path if needed
    if [[ "$sandbox_parent" != /* ]]; then
        sandbox_parent="$(cd "$sandbox_parent" 2>/dev/null && pwd)" || sandbox_parent="$(pwd)/$sandbox_parent"
    fi

    echo "$sandbox_parent/$sandbox_name"
}

# Validate sandbox home location for security
# Rejects system directories and warns about user-level config issues
# Usage: cj::sandbox::validate_home_location <sandbox_path> [config_source]
#   sandbox_path: Full path to sandbox directory
#   config_source: Optional source of config ("user" for ~/.config/claude-jail/config)
# Returns: 0 if valid, 1 if invalid (with error to stderr)
cj::sandbox::validate_home_location() {
    local sandbox_path="$1"
    local config_source="${2:-}"

    [[ -z "$sandbox_path" ]] && {
        echo "Error: Sandbox path cannot be empty" >&2
        return 1
    }

    # Normalize path: remove trailing slashes and resolve to canonical form
    local normalized_path
    # Remove trailing slashes
    normalized_path="${sandbox_path%/}"
    # Handle root specially
    [[ -z "$normalized_path" ]] && normalized_path="/"

    # List of forbidden system directories
    local -a forbidden_dirs=(
        "/"
        "/etc"
        "/home"
        "/root"
        "/usr"
        "/bin"
        "/sbin"
        "/lib"
        "/lib64"
        "/var"
        "/tmp"
        "/boot"
        "/dev"
        "/proc"
        "/sys"
    )

    local forbidden
    for forbidden in "${forbidden_dirs[@]}"; do
        if [[ "$normalized_path" == "$forbidden" ]]; then
            echo "Error: Cannot use system directory as sandbox: $sandbox_path" >&2
            return 1
        fi
    done

    # Warn if sandbox_home is set in user-level config (likely a mistake)
    if [[ "$config_source" == "user" ]]; then
        echo "Warning: CJ_SANDBOX_HOME set in user-level config (~/.config/claude-jail/config)" >&2
        echo "         This affects all projects. Consider using project-level .claude-jail.conf instead." >&2
    fi

    return 0
}

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
