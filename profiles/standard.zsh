# profiles/standard.zsh - Standard isolation (default)
# Selective mounts, preserves PATH. Inspired by mfmayer's gist.
# Good for: Daily use, moderate security needs

_cj_profile_standard() {
    local project_dir="$1"
    local sandbox_home="$2"
    
    cj::unshare user pid uts ipc cgroup
    
    cj::system::base
    cj::system::dns
    cj::system::ssl
    cj::system::users
    
    cj::proc
    cj::dev
    
    cj::tmpfs /tmp
    cj::tmpfs /run
    
    cj::path::bind_all
    
    cj::bind "$project_dir"
    cj::bind "$sandbox_home"
    
    cj::setenv HOME "$sandbox_home"
    cj::setenv XDG_CONFIG_HOME "$sandbox_home/.config"
    cj::setenv XDG_DATA_HOME "$sandbox_home/.local/share"
    cj::setenv XDG_CACHE_HOME "$sandbox_home/.cache"
    cj::setenv PATH "$PATH"
    cj::setenv TERM "${TERM:-xterm-256color}"
    cj::setenv LANG "${LANG:-en_US.UTF-8}"
    cj::setenv SHELL "/bin/bash"
}

cj::profile::register standard _cj_profile_standard
