# claude-jail.plugin.zsh - Run Claude Code in a bubblewrap sandbox
# https://github.com/mbarlow12/claude-jail

0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
typeset -g _CJ_ROOT="${0:A:h}"

source "$_CJ_ROOT/lib/bwrap.zsh"
source "$_CJ_ROOT/lib/config.zsh"
source "$_CJ_ROOT/lib/profiles.zsh"

cj::profile::load_all "$_CJ_ROOT/profiles"

claude-jail() {
    if ! command -v bwrap &>/dev/null; then
        echo "Error: bubblewrap not found. Install: sudo apt install bubblewrap" >&2
        return 1
    fi
    
    local project_dir=""
    local profile=""
    local verbose=false
    local dry_run=false
    local network=""
    local -a cli_ro=()
    local -a cli_rw=()
    local -a claude_args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dir)       project_dir="$2"; shift 2 ;;
            -p|--profile)   profile="$2"; shift 2 ;;
            -v|--verbose)   verbose=true; shift ;;
            --no-network)   network=false; shift ;;
            --network)      network=true; shift ;;
            --ro)           cli_ro+=("$2"); shift 2 ;;
            --rw)           cli_rw+=("$2"); shift 2 ;;
            -h|--help)      _claude_jail_help; return 0 ;;
            --list-profiles) cj::profile::list; return 0 ;;
            --show-config)  cj::config::show; return 0 ;;
            --dry-run)      dry_run=true; shift ;;
            --)             shift; claude_args+=("$@"); break ;;
            -*)             echo "Unknown option: $1" >&2; return 1 ;;
            *)              claude_args+=("$1"); shift ;;
        esac
    done
    
    project_dir="${project_dir:-$(pwd)}"
    project_dir="$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")"
    
    if [[ ! -d "$project_dir" ]]; then
        echo "Error: Not a directory: $project_dir" >&2
        return 1
    fi
    
    profile="${profile:-$(cj::config::get '*' profile standard)}"
    
    if ! cj::profile::exists "$profile"; then
        echo "Error: Unknown profile '$profile'" >&2
        echo "Available: $(cj::profile::list)" >&2
        return 1
    fi
    
    local sandbox_home_name="$(cj::config::get '*' sandbox-home .claude-sandbox)"
    local sandbox_home="$project_dir/$sandbox_home_name"
    
    mkdir -p "$sandbox_home"/{.config,.cache,.local/share,.claude}
    
    if [[ "$(cj::config::get '*' copy-claude-config)" == "true" ]]; then
        if [[ -d ~/.claude ]] && [[ ! -f "$sandbox_home/.claude/.copied" ]]; then
            rsync -a --ignore-existing ~/.claude/ "$sandbox_home/.claude/" 2>/dev/null
            touch "$sandbox_home/.claude/.copied"
        fi
        [[ -f ~/.claude.json ]] && [[ ! -f "$sandbox_home/.claude.json" ]] && \
            cp ~/.claude.json "$sandbox_home/.claude.json" 2>/dev/null
    fi
    
    cj::reset
    cj::profile::apply "$profile" "$project_dir" "$sandbox_home"
    
    cj::worktree::detect_config "$project_dir" "$verbose"

    # Bind-mount credentials for live sync (allows /login to persist)
    local cred_source
    if cred_source="$(cj::credentials::find)"; then
        local cred_target="$sandbox_home/.claude/.credentials.json"
        [[ "$profile" == "paranoid" ]] && cred_target="/sandbox/.claude/.credentials.json"
        touch "$sandbox_home/.claude/.credentials.json"
        cj::bind "$cred_source" "$cred_target"
    fi

    # Pass through environment variables (git, proxy, API key)
    cj::env::passthrough

    if [[ "$network" == "false" ]]; then
        _CJ_NS+=(--unshare-net)
    fi
    
    local -a extra_ro=($(cj::config::get 'paths' extra-ro))
    local -a extra_rw=($(cj::config::get 'paths' extra-rw))

    local p
    for p in "${extra_ro[@]}"; do
        [[ -n "$p" && -e "$p" ]] && cj::ro_bind "$p"
    done
    for p in "${extra_rw[@]}"; do
        [[ -n "$p" && -e "$p" ]] && cj::bind "$p"
    done

    # CLI path options (--ro, --rw)
    for p in "${cli_ro[@]}"; do
        [[ -n "$p" && -e "$p" ]] && cj::ro_bind "$p"
    done
    for p in "${cli_rw[@]}"; do
        [[ -n "$p" && -e "$p" ]] && cj::bind "$p"
    done
    
    local claude_bin
    claude_bin="$(cj::path::find_real claude)" || {
        echo "Error: claude not found in PATH" >&2
        return 1
    }
    
    local chdir_path="$project_dir"
    [[ "$profile" == "paranoid" ]] && chdir_path="/work"
    
    if [[ "$verbose" == true ]]; then
        echo "🔒 claude-jail"
        echo "   Profile: $profile"
        echo "   Project: $project_dir"
        echo "   Sandbox: $sandbox_home"
        echo "   Claude:  $claude_bin"
        echo ""
    fi
    
    cj::chdir "$chdir_path"
    cj::run "$claude_bin" "${claude_args[@]}"
}

claude-jail-shell() {
    local project_dir="${1:-$(pwd)}"
    local profile="${2:-$(cj::config::get '*' profile standard)}"

    project_dir="$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")"
    local sandbox_home="$project_dir/$(cj::config::get '*' sandbox-home .claude-sandbox)"

    mkdir -p "$sandbox_home/.claude"

    cj::reset
    cj::profile::apply "$profile" "$project_dir" "$sandbox_home"

    # Bind-mount credentials for live sync
    local cred_source
    if cred_source="$(cj::credentials::find)"; then
        local cred_target="$sandbox_home/.claude/.credentials.json"
        [[ "$profile" == "paranoid" ]] && cred_target="/sandbox/.claude/.credentials.json"
        touch "$sandbox_home/.claude/.credentials.json"
        cj::bind "$cred_source" "$cred_target"
    fi

    cj::env::passthrough

    local chdir_path="$project_dir"
    [[ "$profile" == "paranoid" ]] && chdir_path="/work"

    echo "🔒 Entering sandbox shell (profile: $profile)"
    echo "   \$HOME = $sandbox_home"
    echo "   Try: ls /home  (should fail)"
    echo ""
    
    cj::chdir "$chdir_path"
    cj::run /bin/bash
}

claude-jail-clean() {
    local project_dir="${1:-$(pwd)}"
    local sandbox_home="$project_dir/$(cj::config::get '*' sandbox-home .claude-sandbox)"
    
    if [[ -d "$sandbox_home" ]]; then
        echo "Removing $sandbox_home ..."
        rm -rf "$sandbox_home"
        echo "Done."
    else
        echo "No sandbox found at $sandbox_home"
    fi
}

claude-jail-debug() {
    local project_dir="${1:-$(pwd)}"
    local profile="${2:-$(cj::config::get '*' profile standard)}"

    project_dir="$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")"
    local sandbox_home="$project_dir/$(cj::config::get '*' sandbox-home .claude-sandbox)"

    local chdir_path="$project_dir"
    [[ "$profile" == "paranoid" ]] && chdir_path="/work"

    cj::reset
    cj::profile::apply "$profile" "$project_dir" "$sandbox_home"
    cj::worktree::detect_config "$project_dir" false

    # Bind-mount credentials for live sync
    local cred_source
    if cred_source="$(cj::credentials::find)"; then
        local cred_target="$sandbox_home/.claude/.credentials.json"
        [[ "$profile" == "paranoid" ]] && cred_target="/sandbox/.claude/.credentials.json"
        cj::bind "$cred_source" "$cred_target"
    fi

    cj::env::passthrough
    cj::chdir "$chdir_path"

    echo "# Profile: $profile"
    echo "# Project: $project_dir"
    echo "# Sandbox: $sandbox_home"
    echo ""
    
    local -a cmd
    cmd=(bwrap --die-with-parent --new-session)
    cmd+=("${_CJ_NS[@]}")
    cmd+=("${_CJ_PRE[@]}")
    cmd+=("${_CJ_BINDS[@]}")
    cmd+=("${_CJ_ENV[@]}")
    cmd+=(-- claude)
    
    printf '%q \\\n    ' "${cmd[@]}"
    echo '"$@"'
}

_claude_jail_help() {
    cat <<'EOF'
claude-jail - Run Claude Code in a bubblewrap sandbox

USAGE
    claude-jail [OPTIONS] [-- CLAUDE_ARGS...]

OPTIONS
    -d, --dir <PATH>      Project directory (default: cwd)
    -p, --profile <NAME>  Isolation profile (default: standard)
    -v, --verbose         Show sandbox info on start
    --network             Force enable network
    --no-network          Disable network access
    --ro <PATH>           Add read-only path (can repeat)
    --rw <PATH>           Add read-write path (can repeat)
    --list-profiles       List available profiles
    --show-config         Show current configuration
    -h, --help            Show this help

PROFILES
    minimal     Fast, basic isolation. Mounts /etc read-only.
    standard    Balanced. Selective /etc, preserves PATH. (default)
    paranoid    Maximum isolation. Fake paths at /work and /sandbox.

CONFIGURATION (in ~/.zshrc, before plugin loads)
    zstyle ':claude-jail:*' profile standard
    zstyle ':claude-jail:*' network true
    zstyle ':claude-jail:*' sandbox-home .claude-sandbox
    zstyle ':claude-jail:*' copy-claude-config true
    zstyle ':claude-jail:paths' extra-ro /path/to/libs /another/path
    zstyle ':claude-jail:paths' extra-rw /path/to/scratch

COMMANDS
    claude-jail           Run claude in sandbox
    claude-jail-shell     Open bash in sandbox (for testing)
    claude-jail-clean     Remove .claude-sandbox directory
    claude-jail-debug     Print bwrap command without running

EXAMPLES
    claude-jail                       # Run in current directory
    claude-jail -d ~/project          # Run in specific directory
    claude-jail -p paranoid           # Maximum isolation
    claude-jail -v -- --print "hi"    # Verbose, pass args to claude
    claude-jail-debug paranoid        # See what bwrap would run

SECURITY
    Inside the sandbox:
    - $HOME points to .claude-sandbox/ (or /sandbox in paranoid mode)
    - /home, /root don't exist
    - System dirs are read-only
    - Only project directory is writable

    Even `rm -rf ~` or `rm -rf /` cannot harm your real system.
EOF
}

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
            '-h[Show help]' \
            '--help[Show help]' \
            '*::claude arguments:_default'
    }
fi
