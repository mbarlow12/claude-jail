# claude-jail.plugin.zsh - Zsh plugin wrapper for claude-jail
# https://github.com/mbarlow12/claude-jail
# This is a thin wrapper around the bash core library

0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
typeset -g _CJ_ROOT="${0:A:h}"

# Source bash core libraries
source "$_CJ_ROOT/lib/bwrap.sh"
source "$_CJ_ROOT/lib/config.sh"
source "$_CJ_ROOT/lib/profiles.sh"

# Load all profiles
cj::profile::load_all "$_CJ_ROOT/profiles"

# Zsh-specific: support zstyle configuration (backward compatibility)
# If user has zstyle config, migrate it to environment variables
if (( $+functions[zstyle] )); then
    # Only apply if CJ_* variables aren't already set
    local _zs_value
    if [[ -z "$CJ_PROFILE" ]]; then
        zstyle -s ':claude-jail:*' profile _zs_value 2>/dev/null && export CJ_PROFILE="$_zs_value"
    fi
    if [[ -z "$CJ_NETWORK" ]]; then
        zstyle -b ':claude-jail:*' network _zs_value 2>/dev/null && export CJ_NETWORK="$([[ $_zs_value == yes ]] && echo true || echo false)"
    fi
    if [[ -z "$CJ_SANDBOX_HOME" ]]; then
        zstyle -s ':claude-jail:*' sandbox-home _zs_value 2>/dev/null && export CJ_SANDBOX_HOME="$_zs_value"
    fi
    if [[ -z "$CJ_COPY_CLAUDE_CONFIG" ]]; then
        zstyle -b ':claude-jail:*' copy-claude-config _zs_value 2>/dev/null && export CJ_COPY_CLAUDE_CONFIG="$([[ $_zs_value == yes ]] && echo true || echo false)"
    fi
    if [[ -z "$CJ_VERBOSE" ]]; then
        zstyle -b ':claude-jail:*' verbose _zs_value 2>/dev/null && export CJ_VERBOSE="$([[ $_zs_value == yes ]] && echo true || echo false)"
    fi

    # Array values
    local -a _zs_array
    if [[ -z "$CJ_EXTRA_RO" ]]; then
        zstyle -a ':claude-jail:paths' extra-ro _zs_array 2>/dev/null && export CJ_EXTRA_RO="${(j.:.)_zs_array}"
    fi
    if [[ -z "$CJ_EXTRA_RW" ]]; then
        zstyle -a ':claude-jail:paths' extra-rw _zs_array 2>/dev/null && export CJ_EXTRA_RW="${(j.:.)_zs_array}"
    fi
fi

# Re-initialize config after potentially loading zstyle values
cj::config::init

# Zsh command wrappers that delegate to bash script
claude-jail() {
    "$_CJ_ROOT/bin/claude-jail" "$@"
}

claude-jail-shell() {
    case "$1" in
        -h|--help)
            echo "Usage: claude-jail-shell [PROJECT_DIR] [PROFILE]"
            echo ""
            echo "Open an interactive bash shell inside the sandbox for testing."
            echo ""
            echo "Arguments:"
            echo "  PROJECT_DIR    Project directory (default: current directory)"
            echo "  PROFILE        Profile to use (default: from config)"
            echo ""
            echo "Example:"
            echo "  claude-jail-shell ~/myproject paranoid"
            return 0
            ;;
    esac
    "$_CJ_ROOT/bin/claude-jail" shell "$@"
}

claude-jail-clean() {
    case "$1" in
        -h|--help)
            echo "Usage: claude-jail-clean [PROJECT_DIR]"
            echo ""
            echo "Remove the .claude-sandbox directory from a project."
            echo ""
            echo "Arguments:"
            echo "  PROJECT_DIR    Project directory (default: current directory)"
            echo ""
            echo "Example:"
            echo "  claude-jail-clean ~/myproject"
            return 0
            ;;
    esac
    "$_CJ_ROOT/bin/claude-jail" clean "$@"
}

claude-jail-debug() {
    case "$1" in
        -h|--help)
            echo "Usage: claude-jail-debug [PROJECT_DIR] [PROFILE]"
            echo ""
            echo "Print the bwrap command that would be executed, without running it."
            echo ""
            echo "Arguments:"
            echo "  PROJECT_DIR    Project directory (default: current directory)"
            echo "  PROFILE        Profile to use (default: from config)"
            echo ""
            echo "Example:"
            echo "  claude-jail-debug ~/myproject paranoid"
            return 0
            ;;
    esac
    "$_CJ_ROOT/bin/claude-jail" debug "$@"
}

# Zsh completion
if [[ -n "$ZSH_VERSION" ]]; then
    compdef _claude_jail claude-jail

    _claude_jail() {
        local -a opts profiles
        profiles=(${(f)"$(cj::profile::list)"})

        _arguments -s \
            '-d[Project directory]:directory:_files -/' \
            '--dir[Project directory]:directory:_files -/' \
            "-p[Profile]:profile:($profiles)" \
            "--profile[Profile]:profile:($profiles)" \
            '-v[Verbose output]' \
            '--verbose[Verbose output]' \
            '--network[Enable network]' \
            '--no-network[Disable network]' \
            '*--ro[Read-only path]:path:_files -/' \
            '*--rw[Read-write path]:path:_files -/' \
            '--list-profiles[List profiles]' \
            '--show-config[Show configuration]' \
            '--help-config[Show configuration help]' \
            '-h[Show help]' \
            '--help[Show help]' \
            '*::claude arguments:_default'
    }
fi
