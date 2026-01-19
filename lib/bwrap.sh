#!/usr/bin/env bash
# lib/bwrap.sh - Core bubblewrap utilities (pure bash)
# Building blocks for constructing bwrap argument lists

declare -gA _CJ_SEEN=()
declare -ga _CJ_PRE=()
declare -ga _CJ_BINDS=()
declare -ga _CJ_ENV=()
declare -ga _CJ_NS=()

cj::reset() {
    _CJ_SEEN=()
    _CJ_PRE=()
    _CJ_BINDS=()
    _CJ_ENV=()
    _CJ_NS=()
}

cj::_ensure_parent() {
    local target="$1"
    [[ -z "$target" ]] && return

    local build=""
    local part

    # Split path by / and iterate
    IFS='/' read -ra parts <<< "${target#/}"
    for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue
        build="$build/$part"
        [[ -n "${_CJ_SEEN[dir:$build]:-}" ]] && continue
        _CJ_PRE+=(--dir "$build")
        _CJ_SEEN[dir:$build]=1
    done
}

cj::ro_bind() {
    local src="$1" dst="${2:-$1}"
    [[ -z "$src" || ! -e "$src" ]] && return 1
    [[ -n "${_CJ_SEEN[bind:$dst]:-}" ]] && return 0

    src="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    cj::_ensure_parent "$(dirname "$dst")"
    _CJ_BINDS+=(--ro-bind "$src" "$dst")
    _CJ_SEEN[bind:$dst]=1
}

cj::bind() {
    local src="$1" dst="${2:-$1}"
    [[ -z "$src" || ! -e "$src" ]] && return 1
    [[ -n "${_CJ_SEEN[bind:$dst]:-}" ]] && return 0

    src="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    cj::_ensure_parent "$(dirname "$dst")"
    _CJ_BINDS+=(--bind "$src" "$dst")
    _CJ_SEEN[bind:$dst]=1
}

cj::tmpfs() {
    local path="$1"
    cj::_ensure_parent "$path"
    _CJ_BINDS+=(--tmpfs "$path")
}

cj::symlink() {
    local target="$1" link="$2"
    _CJ_SEEN[dir:$link]=1
    _CJ_BINDS+=(--symlink "$target" "$link")
}

cj::dev() {
    local path="${1:-/dev}"
    _CJ_BINDS+=(--dev "$path")
}

cj::proc() {
    local path="${1:-/proc}"
    _CJ_BINDS+=(--proc "$path")
}

cj::setenv() {
    local name="$1" value="$2"
    _CJ_ENV+=(--setenv "$name" "$value")
}

cj::chdir() {
    local path="$1"
    _CJ_BINDS+=(--chdir "$path")
}

cj::unshare() {
    local ns
    for ns in "$@"; do
        case "$ns" in
            all)     _CJ_NS+=(--unshare-all) ;;
            user)    _CJ_NS+=(--unshare-user) ;;
            pid)     _CJ_NS+=(--unshare-pid) ;;
            net)     _CJ_NS+=(--unshare-net) ;;
            ipc)     _CJ_NS+=(--unshare-ipc) ;;
            uts)     _CJ_NS+=(--unshare-uts) ;;
            cgroup)  _CJ_NS+=(--unshare-cgroup) ;;
        esac
    done
}

cj::share() {
    local ns
    for ns in "$@"; do
        case "$ns" in
            net) _CJ_NS+=(--share-net) ;;
        esac
    done
}

cj::system::base() {
    cj::ro_bind /usr

    if [[ -L /bin ]]; then
        cj::symlink usr/bin /bin
    elif [[ -d /bin ]]; then
        cj::ro_bind /bin
    fi

    if [[ -L /lib ]]; then
        cj::symlink usr/lib /lib
    elif [[ -d /lib ]]; then
        cj::ro_bind /lib
    fi

    if [[ -L /lib64 ]]; then
        cj::symlink usr/lib64 /lib64
    elif [[ -d /lib64 ]]; then
        cj::ro_bind /lib64
    fi

    if [[ -L /sbin ]]; then
        cj::symlink usr/sbin /sbin
    elif [[ -d /sbin ]]; then
        cj::ro_bind /sbin
    fi

    [[ -d /etc/alternatives ]] && cj::ro_bind /etc/alternatives
}

cj::system::dns() {
    local f
    for f in /etc/resolv.conf /etc/hosts /etc/nsswitch.conf /etc/host.conf /etc/gai.conf; do
        [[ -f "$f" ]] && cj::ro_bind "$f"
    done
}

cj::system::ssl() {
    [[ -d /etc/ssl ]] && cj::ro_bind /etc/ssl
    [[ -d /etc/ca-certificates ]] && cj::ro_bind /etc/ca-certificates
    [[ -d /etc/pki ]] && cj::ro_bind /etc/pki
    [[ -f /etc/ca-certificates.conf ]] && cj::ro_bind /etc/ca-certificates.conf
}

cj::system::users() {
    [[ -f /etc/passwd ]] && cj::ro_bind /etc/passwd
    [[ -f /etc/group ]] && cj::ro_bind /etc/group
    [[ -f /etc/localtime ]] && cj::ro_bind /etc/localtime
}

cj::system::run() {
    [[ -d /run/user/$UID ]] && cj::ro_bind /run/user/$UID || true
}

cj::path::bind_all() {
    local d
    IFS=':' read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] && cj::ro_bind "$d" || true
    done
}

cj::path::find_real() {
    local name="$1"
    local bin real_bin

    bin="$(command -v "$name" 2>/dev/null)" || return 1
    real_bin="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"

    [[ -d "$(dirname "$real_bin")" ]] && cj::ro_bind "$(dirname "$real_bin")" || true
    echo "$bin"
}

cj::worktree::detect_config() {
    local project_dir="$1"
    local parent
    parent="$(dirname "$project_dir")"
    local verbose="${2:-false}"

    [[ -z "$project_dir" ]] && return 1

    if [[ -d "$parent/.claude" && ! -d "$project_dir/.claude" ]]; then
        [[ "$verbose" == true ]] && echo "   Worktree: binding $parent/.claude -> $project_dir/.claude"
        cj::bind "$parent/.claude" "$project_dir/.claude"
    fi

    if [[ -f "$parent/CLAUDE.md" && ! -f "$project_dir/CLAUDE.md" ]]; then
        [[ "$verbose" == true ]] && echo "   Worktree: binding $parent/CLAUDE.md -> $project_dir/CLAUDE.md"
        cj::bind "$parent/CLAUDE.md" "$project_dir/CLAUDE.md"
    fi

    if [[ -f "$parent/.claudeignore" && ! -f "$project_dir/.claudeignore" ]]; then
        [[ "$verbose" == true ]] && echo "   Worktree: binding $parent/.claudeignore -> $project_dir/.claudeignore"
        cj::bind "$parent/.claudeignore" "$project_dir/.claudeignore"
    fi
}

# =============================================================================
# Git worktree detection functions
# =============================================================================

# Get the main repository root from a worktree
# For worktrees, follows gitdir -> commondir to find main .git
# For primary clones, returns the project directory itself
# Usage: cj::git::get_main_repo_root <project_dir>
# Outputs: Path to main repository root (containing real .git directory)
# Returns: 0 if git repo found, 1 otherwise
cj::git::get_main_repo_root() {
    local project_dir="$1"
    local git_path="$project_dir/.git"

    [[ -z "$project_dir" ]] && return 1

    # Not a git repo
    [[ ! -e "$git_path" ]] && return 1

    # Primary clone - .git is a directory
    if [[ -d "$git_path" ]]; then
        echo "$project_dir"
        return 0
    fi

    # Worktree - .git is a file containing gitdir path
    if [[ -f "$git_path" ]]; then
        local gitdir_line gitdir_path commondir_path main_git_dir

        # Parse "gitdir: <path>" from .git file
        gitdir_line="$(head -n1 "$git_path")"
        if [[ "$gitdir_line" =~ ^gitdir:\ (.+)$ ]]; then
            gitdir_path="${BASH_REMATCH[1]}"

            # Resolve relative paths
            if [[ "$gitdir_path" != /* ]]; then
                gitdir_path="$(cd "$project_dir" && cd "$(dirname "$gitdir_path")" && pwd)/$(basename "$gitdir_path")"
            fi

            # Check for commondir file (points to main .git)
            if [[ -f "$gitdir_path/commondir" ]]; then
                commondir_path="$(cat "$gitdir_path/commondir")"
                # Resolve relative commondir path
                if [[ "$commondir_path" != /* ]]; then
                    main_git_dir="$(cd "$gitdir_path" && cd "$commondir_path" && pwd)"
                else
                    main_git_dir="$commondir_path"
                fi
                # Return parent of .git directory
                echo "$(dirname "$main_git_dir")"
                return 0
            fi
        fi
    fi

    return 1
}

# Detect git worktree and bind main .git directory if needed
# For worktrees, binds the main repository's .git directory
# For primary clones, no additional binding needed
# Usage: cj::git::detect_worktree <project_dir> [readonly] [verbose] [manual_git_root]
#   project_dir: The project directory to check
#   readonly: "true" to bind read-only (default: "false" for read-write)
#   verbose: "true" to print debug info (default: "false")
#   manual_git_root: Optional manual override for main git root
# Returns: 0 on success, 1 if not a git repo
cj::git::detect_worktree() {
    local project_dir="$1"
    local readonly="${2:-false}"
    local verbose="${3:-false}"
    local manual_git_root="${4:-}"
    local git_path="$project_dir/.git"
    local main_repo_root main_git_dir

    [[ -z "$project_dir" ]] && return 1

    # Not a git repo
    [[ ! -e "$git_path" ]] && return 1

    # Use manual override if provided
    if [[ -n "$manual_git_root" ]]; then
        main_repo_root="$manual_git_root"
        if [[ ! -d "$main_repo_root/.git" ]]; then
            echo "Warning: Manual git root $main_repo_root does not contain .git directory" >&2
            return 1
        fi
    else
        # Primary clone - .git is a directory, already part of project_dir binding
        if [[ -d "$git_path" ]]; then
            [[ "$verbose" == true ]] && echo "   Git: primary clone, .git is part of project"
            return 0
        fi

        # Worktree - need to find and bind main .git
        main_repo_root="$(cj::git::get_main_repo_root "$project_dir")" || return 1
    fi

    main_git_dir="$main_repo_root/.git"

    # Don't bind if main_git_dir is already inside project_dir (already bound)
    if [[ "$main_git_dir" == "$project_dir"/* ]]; then
        [[ "$verbose" == true ]] && echo "   Git: main .git is inside project directory"
        return 0
    fi

    # Bind the main .git directory
    if [[ "$readonly" == true ]]; then
        [[ "$verbose" == true ]] && echo "   Git: binding $main_git_dir (read-only)"
        cj::ro_bind "$main_git_dir"
    else
        [[ "$verbose" == true ]] && echo "   Git: binding $main_git_dir (read-write)"
        cj::bind "$main_git_dir"
    fi

    return 0
}

cj::build() {
    local -a cmd=(bwrap)
    cmd+=(--die-with-parent --new-session)
    cmd+=("${_CJ_NS[@]}")
    cmd+=("${_CJ_PRE[@]}")
    cmd+=("${_CJ_BINDS[@]}")
    cmd+=("${_CJ_ENV[@]}")
    echo "${cmd[@]}"
}

cj::exec() {
    local -a cmd
    cmd=(bwrap --die-with-parent --new-session)
    cmd+=("${_CJ_NS[@]}")
    cmd+=("${_CJ_PRE[@]}")
    cmd+=("${_CJ_BINDS[@]}")
    cmd+=("${_CJ_ENV[@]}")
    cmd+=(-- "$@")
    exec "${cmd[@]}"
}

cj::run() {
    local -a cmd
    cmd=(bwrap --die-with-parent --new-session)
    cmd+=("${_CJ_NS[@]}")
    cmd+=("${_CJ_PRE[@]}")
    cmd+=("${_CJ_BINDS[@]}")
    cmd+=("${_CJ_ENV[@]}")
    cmd+=(-- "$@")
    "${cmd[@]}"
}

cj::env::passthrough() {
    # Git identity
    [[ -n "${GIT_AUTHOR_NAME:-}" ]] && cj::setenv GIT_AUTHOR_NAME "$GIT_AUTHOR_NAME"
    [[ -n "${GIT_AUTHOR_EMAIL:-}" ]] && cj::setenv GIT_AUTHOR_EMAIL "$GIT_AUTHOR_EMAIL"
    [[ -n "${GIT_COMMITTER_NAME:-}" ]] && cj::setenv GIT_COMMITTER_NAME "$GIT_COMMITTER_NAME"
    [[ -n "${GIT_COMMITTER_EMAIL:-}" ]] && cj::setenv GIT_COMMITTER_EMAIL "$GIT_COMMITTER_EMAIL"

    # Proxy settings
    [[ -n "${http_proxy:-}" ]] && cj::setenv http_proxy "$http_proxy"
    [[ -n "${https_proxy:-}" ]] && cj::setenv https_proxy "$https_proxy"
    [[ -n "${HTTP_PROXY:-}" ]] && cj::setenv HTTP_PROXY "$HTTP_PROXY"
    [[ -n "${HTTPS_PROXY:-}" ]] && cj::setenv HTTPS_PROXY "$HTTPS_PROXY"
    [[ -n "${no_proxy:-}" ]] && cj::setenv no_proxy "$no_proxy"
    [[ -n "${NO_PROXY:-}" ]] && cj::setenv NO_PROXY "$NO_PROXY"

    # API key for direct API users
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && cj::setenv ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"

    # Timezone
    [[ -n "${TZ:-}" ]] && cj::setenv TZ "$TZ"

    # Always return success (conditionals above may be false)
    return 0
}

cj::credentials::find() {
    local cred_file dir
    # Check in order of precedence
    for dir in \
        "${CLAUDE_CONFIG_DIR:-}" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/claude" \
        "$HOME/.claude"
    do
        [[ -z "$dir" ]] && continue
        cred_file="$dir/.credentials.json"
        [[ -f "$cred_file" ]] && { echo "$cred_file"; return 0; }
    done
    return 1
}
