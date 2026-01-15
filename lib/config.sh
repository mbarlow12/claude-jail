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
    [copy_claude_config]="true"
    [verbose]="false"
)

# User-defined extra paths
declare -ga _CJ_EXTRA_RO=()
declare -ga _CJ_EXTRA_RW=()
declare -ga _CJ_BLOCKED=()

cj::config::_load_file() {
    local config_file="$1"
    [[ ! -f "$config_file" ]] && return 1

    # Source the config file in a subshell to validate syntax
    if ! ( source "$config_file" ) &>/dev/null; then
        echo "Warning: Failed to parse config file: $config_file" >&2
        return 1
    fi

    # Source the config file to load variables
    source "$config_file"
    return 0
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
    [[ -n "${CJ_COPY_CLAUDE_CONFIG:-}" ]] && _CJ_CONFIG[copy_claude_config]="$CJ_COPY_CLAUDE_CONFIG"
    [[ -n "${CJ_VERBOSE:-}" ]] && _CJ_CONFIG[verbose]="$CJ_VERBOSE"

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
    echo "  copy-claude-config: $(cj::config::get copy_claude_config)"
    echo "  verbose:            $(cj::config::get verbose)"
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
   CJ_SANDBOX_HOME=.claude-sandbox  # Sandbox directory name
   CJ_COPY_CLAUDE_CONFIG=true   # Copy ~/.claude on first run
   CJ_VERBOSE=false             # Verbose output
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
   CJ_SANDBOX_HOME=.claude-sandbox
   CJ_COPY_CLAUDE_CONFIG=true
   CJ_VERBOSE=false
   CJ_EXTRA_RO=(/path/to/libs /another/path)
   CJ_EXTRA_RW=(/path/to/scratch)
   ```

3. CLI arguments (override everything):
   --profile, --network, --no-network, --ro, --rw, etc.

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
EOF
}

# Initialize configuration on load
cj::config::init
