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
