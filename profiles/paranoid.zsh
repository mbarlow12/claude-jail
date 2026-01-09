# profiles/paranoid.zsh - Maximum isolation
# Absolute minimum mounts, fake home in /sandbox
# Good for: Untrusted code, security-sensitive work

_cj_profile_paranoid() {
    local project_dir="$1"
    local sandbox_home="$2"
    
    cj::unshare all
    cj::share net  # Still need network for API
    
    cj::ro_bind /usr
    cj::ro_bind /bin
    cj::ro_bind /lib
    [[ -d /lib64 ]] && cj::ro_bind /lib64
    [[ -L /lib64 ]] && cj::symlink usr/lib64 /lib64
    
    cj::ro_bind /etc/resolv.conf
    cj::ro_bind /etc/hosts
    cj::ro_bind /etc/ssl
    [[ -d /etc/ca-certificates ]] && cj::ro_bind /etc/ca-certificates
    
    cj::proc
    cj::dev
    cj::tmpfs /tmp
    
    cj::bind "$project_dir" /work
    cj::bind "$sandbox_home" /sandbox
    
    cj::setenv HOME /sandbox
    cj::setenv XDG_CONFIG_HOME /sandbox/.config
    cj::setenv XDG_DATA_HOME /sandbox/.local/share
    cj::setenv XDG_CACHE_HOME /sandbox/.cache
    cj::setenv PATH "/usr/local/bin:/usr/bin:/bin"
    cj::setenv TERM "${TERM:-xterm-256color}"
    cj::setenv LANG "C.UTF-8"
    cj::setenv SHELL "/bin/sh"
    cj::setenv TMPDIR /tmp
}

cj::profile::register paranoid _cj_profile_paranoid
