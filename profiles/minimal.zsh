# profiles/minimal.zsh - Minimal isolation
# Fast startup, basic protection. Inspired by akashakya's HN comment.
# Good for: Quick iterations, trusted codebases

_cj_profile_minimal() {
    local project_dir="$1"
    local sandbox_home="$2"
    
    cj::unshare all
    cj::share net
    
    cj::ro_bind /usr
    cj::ro_bind /etc
    cj::ro_bind /run
    
    cj::proc
    cj::dev
    
    [[ -L /lib64 ]] && cj::symlink usr/lib64 /lib64
    [[ -d /lib64 && ! -L /lib64 ]] && cj::ro_bind /lib64
    
    cj::tmpfs /tmp
    
    cj::bind "$project_dir"
    cj::bind "$sandbox_home"
    
    cj::setenv HOME "$sandbox_home"
    cj::setenv PATH "/usr/local/bin:/usr/bin:/bin"
    cj::setenv TERM "${TERM:-xterm-256color}"
}

cj::profile::register minimal _cj_profile_minimal
