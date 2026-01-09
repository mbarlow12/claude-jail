# lib/bwrap.zsh - Core bubblewrap utilities
# Building blocks for constructing bwrap argument lists

typeset -gA _CJ_SEEN=()
typeset -ga _CJ_PRE=()
typeset -ga _CJ_BINDS=()
typeset -ga _CJ_ENV=()
typeset -ga _CJ_NS=()

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
    for part in ${(s:/:)target#/}; do
        [[ -z "$part" ]] && continue
        build="$build/$part"
        [[ -n "${_CJ_SEEN[dir:$build]}" ]] && continue
        _CJ_PRE+=(--dir "$build")
        _CJ_SEEN[dir:$build]=1
    done
}

cj::ro_bind() {
    local src="$1" dst="${2:-$1}"
    [[ -z "$src" || ! -e "$src" ]] && return 1
    [[ -n "${_CJ_SEEN[bind:$dst]}" ]] && return 0
    
    src="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    cj::_ensure_parent "${dst:h}"
    _CJ_BINDS+=(--ro-bind "$src" "$dst")
    _CJ_SEEN[bind:$dst]=1
}

cj::bind() {
    local src="$1" dst="${2:-$1}"
    [[ -z "$src" || ! -e "$src" ]] && return 1
    [[ -n "${_CJ_SEEN[bind:$dst]}" ]] && return 0
    
    src="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    cj::_ensure_parent "${dst:h}"
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
    [[ -d /run/user/$UID ]] && cj::ro_bind /run/user/$UID
}

cj::path::bind_all() {
    local d
    for d in ${(s/:/)PATH}; do
        [[ -d "$d" ]] && cj::ro_bind "$d"
    done
}

cj::path::find_real() {
    local name="$1"
    local bin real_bin
    
    bin="$(command -v "$name" 2>/dev/null)" || return 1
    real_bin="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
    
    [[ -d "${real_bin:h}" ]] && cj::ro_bind "${real_bin:h}"
    echo "$bin"
}

cj::worktree::detect_config() {
    local project_dir="$1"
    local parent="${project_dir:h}"
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
