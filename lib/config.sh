#!/usr/bin/env bash
# lib/config.sh - Configuration via environment variables and config files
# Precedence: CLI args > Environment vars > Config file > Defaults

# Configuration file locations (checked in order)
declare -ga _CJ_CONFIG_PATHS=(
    "${CJ_CONFIG_FILE:-}"
    ".claude-jail.conf"
    "${XDG_CONFIG_HOME:-$HOME/.config}/claude-jail/config"
    "$HOME/.claude-jail.conf"
)

# Default configuration values
declare -gA _CJ_CONFIG=(
    [profile]="standard"
    [network]="true"
    [sandbox_home]=".claude-sandbox"
    [sandbox_name]=".claude-sandbox"
    [copy_claude_config]="true"
    [verbose]="false"
    [git_worktree_ro]="false"
)

# Track which config file was loaded (for warnings)
declare -g _CJ_CONFIG_SOURCE=""

# User-defined extra paths
declare -ga _CJ_EXTRA_RO=()
declare -ga _CJ_EXTRA_RW=()
declare -ga _CJ_BLOCKED=()

cj::config::_load_file() {
    local config_file="$1"
    [[ ! -f "$config_file" ]] && return 1

    # Source the config file in a subshell to validate syntax
    # shellcheck disable=SC1090
    if ! ( source "$config_file" ) &>/dev/null; then
        echo "Warning: Failed to parse config file: $config_file" >&2
        return 1
    fi

    # Track config source for warnings
    _CJ_CONFIG_SOURCE="$config_file"

    # Source the config file to load variables
    # shellcheck disable=SC1090
    source "$config_file"
    return 0
}

# Check if a config option was set in user-level config
# Usage: cj::config::is_user_level_config
# Returns: 0 if user-level config loaded, 1 otherwise
cj::config::is_user_level_config() {
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/claude-jail/config"
    local home_config="$HOME/.claude-jail.conf"
    [[ "$_CJ_CONFIG_SOURCE" == "$user_config" || "$_CJ_CONFIG_SOURCE" == "$home_config" ]]
}

cj::config::init() {
    local config_file

    # Try to load first available config file
    for config_file in "${_CJ_CONFIG_PATHS[@]}"; do
        [[ -z "$config_file" ]] && continue
        if cj::config::_load_file "$config_file"; then
            # Config file loaded successfully
            break
        fi
    done

    # Override defaults with environment variables if set
    [[ -n "${CJ_PROFILE:-}" ]] && _CJ_CONFIG[profile]="$CJ_PROFILE"
    [[ -n "${CJ_NETWORK:-}" ]] && _CJ_CONFIG[network]="$CJ_NETWORK"
    [[ -n "${CJ_SANDBOX_HOME:-}" ]] && _CJ_CONFIG[sandbox_home]="$CJ_SANDBOX_HOME"
    [[ -n "${CJ_SANDBOX_NAME:-}" ]] && _CJ_CONFIG[sandbox_name]="$CJ_SANDBOX_NAME"
    [[ -n "${CJ_COPY_CLAUDE_CONFIG:-}" ]] && _CJ_CONFIG[copy_claude_config]="$CJ_COPY_CLAUDE_CONFIG"
    [[ -n "${CJ_VERBOSE:-}" ]] && _CJ_CONFIG[verbose]="$CJ_VERBOSE"
    [[ -n "${CJ_GIT_WORKTREE_RO:-}" ]] && _CJ_CONFIG[git_worktree_ro]="$CJ_GIT_WORKTREE_RO"

    # Load extra paths from environment if set
    if [[ -n "${CJ_EXTRA_RO:-}" ]]; then
        IFS=':' read -ra _CJ_EXTRA_RO <<< "$CJ_EXTRA_RO"
    fi
    if [[ -n "${CJ_EXTRA_RW:-}" ]]; then
        IFS=':' read -ra _CJ_EXTRA_RW <<< "$CJ_EXTRA_RW"
    fi
    if [[ -n "${CJ_BLOCKED:-}" ]]; then
        IFS=':' read -ra _CJ_BLOCKED <<< "$CJ_BLOCKED"
    fi
}

cj::config::get() {
    local key="$1"
    local default="${2:-}"

    if [[ -n "${_CJ_CONFIG[$key]:-}" ]]; then
        echo "${_CJ_CONFIG[$key]}"
    else
        echo "$default"
    fi
}

cj::config::get_bool() {
    local key="$1"
    local default="${2:-false}"
    local value

    value="$(cj::config::get "$key" "$default")"
    [[ "$value" == "true" || "$value" == "yes" || "$value" == "1" ]]
}

cj::config::set() {
    local key="$1"
    local value="$2"
    _CJ_CONFIG[$key]="$value"
}

cj::config::get_extra_ro() {
    echo "${_CJ_EXTRA_RO[@]}"
}

cj::config::get_extra_rw() {
    echo "${_CJ_EXTRA_RW[@]}"
}

cj::config::get_blocked() {
    echo "${_CJ_BLOCKED[@]}"
}

cj::config::add_extra_ro() {
    _CJ_EXTRA_RO+=("$@")
}

cj::config::add_extra_rw() {
    _CJ_EXTRA_RW+=("$@")
}

cj::config::show() {
    echo "claude-jail configuration:"
    echo "  profile:            $(cj::config::get profile)"
    echo "  network:            $(cj::config::get network)"
    echo "  sandbox-home:       $(cj::config::get sandbox_home)"
    echo "  sandbox-name:       $(cj::config::get sandbox_name)"
    echo "  copy-claude-config: $(cj::config::get copy_claude_config)"
    echo "  verbose:            $(cj::config::get verbose)"
    echo "  git-worktree-ro:    $(cj::config::get git_worktree_ro)"
    echo ""
    if [[ ${#_CJ_EXTRA_RO[@]} -gt 0 ]]; then
        echo "Extra read-only paths:"
        for path in "${_CJ_EXTRA_RO[@]}"; do
            echo "  - $path"
        done
        echo ""
    fi
    if [[ ${#_CJ_EXTRA_RW[@]} -gt 0 ]]; then
        echo "Extra read-write paths:"
        for path in "${_CJ_EXTRA_RW[@]}"; do
            echo "  - $path"
        done
        echo ""
    fi
    if [[ ${#_CJ_BLOCKED[@]} -gt 0 ]]; then
        echo "Blocked paths:"
        for path in "${_CJ_BLOCKED[@]}"; do
            echo "  - $path"
        done
    fi
}

cj::config::help() {
    cat <<'EOF'
CONFIGURATION

claude-jail can be configured using:

1. Environment variables (highest priority):
   CJ_PROFILE=standard          # Profile to use
   CJ_NETWORK=true              # Enable/disable network
   CJ_SANDBOX_HOME=/path        # Parent directory for sandbox (default: cwd)
   CJ_SANDBOX_NAME=.claude-sandbox  # Sandbox directory name
   CJ_COPY_CLAUDE_CONFIG=true   # Copy ~/.claude on first run
   CJ_VERBOSE=false             # Verbose output
   CJ_GIT_WORKTREE_RO=false     # Bind main .git read-only in worktrees
   CJ_EXTRA_RO=/path1:/path2    # Extra read-only paths (colon-separated)
   CJ_EXTRA_RW=/path1:/path2    # Extra read-write paths (colon-separated)
   CJ_BLOCKED=/path1:/path2     # Blocked paths (colon-separated)
   CJ_CONFIG_FILE=/path/to/config  # Custom config file location

2. Config file (checked in order):
   - ./.claude-jail.conf
   - ~/.config/claude-jail/config
   - ~/.claude-jail.conf

   Config file format (bash syntax):
   ```bash
   CJ_PROFILE=standard
   CJ_NETWORK=true
   CJ_SANDBOX_HOME=/path/to/sandboxes  # Parent directory
   CJ_SANDBOX_NAME=.claude-sandbox     # Directory name
   CJ_COPY_CLAUDE_CONFIG=true
   CJ_VERBOSE=false
   CJ_GIT_WORKTREE_RO=false
   CJ_EXTRA_RO=(/path/to/libs /another/path)
   CJ_EXTRA_RW=(/path/to/scratch)
   ```

   NOTE: Setting CJ_SANDBOX_HOME in user-level config (~/.config/claude-jail/config)
   affects all projects and is usually not what you want. Prefer project-level
   .claude-jail.conf for project-specific sandbox locations.

3. CLI arguments (override everything):
   --profile, --network, --no-network, --ro, --rw, etc.
   --sandbox-home, --sandbox-name, --git-root, --git-ro

GIT WORKTREE SUPPORT

claude-jail automatically detects git worktrees and binds the main .git directory.
This allows full git operations in worktrees. By default, the main .git is bound
read-write. Use --git-ro or CJ_GIT_WORKTREE_RO=true for read-only binding.

EXAMPLES

# Set profile via environment variable
export CJ_PROFILE=paranoid
claude-jail

# Use custom config file
export CJ_CONFIG_FILE=~/my-claude-config
claude-jail

# Add extra read-only paths
export CJ_EXTRA_RO="/usr/local/mylib:/opt/tools"
claude-jail

# Override via CLI (highest priority)
CJ_PROFILE=standard claude-jail --profile paranoid  # Uses paranoid

# Worktree example: sandbox shared between worktrees
cd ~/projects/myrepo-worktrees
claude-jail -d feat-branch   # Sandbox at ./cwd/.claude-sandbox
claude-jail -d main          # Same sandbox location (shared)

# Override sandbox location
claude-jail --sandbox-home /tmp/sandboxes --sandbox-name mysandbox

# Manual git root (if auto-detection fails)
claude-jail -d feat-branch --git-root ./main
EOF
}

# Initialize configuration on load
cj::config::init
