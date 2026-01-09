# profiles/dev.zsh - Developer workstation profile
# Full toolchain access, worktree-aware. Best for daily development.
# Good for: mise, cargo, uv, node version managers

_cj_profile_dev() {
    local project_dir="$1"
    local sandbox_home="$2"
    
    cj::unshare user pid uts ipc cgroup
    
    cj::system::base
    cj::system::dns
    cj::system::ssl
    cj::system::users
    
    [[ -d /etc/alternatives ]] && cj::ro_bind /etc/alternatives
    
    cj::proc
    cj::dev
    
    cj::tmpfs /tmp
    cj::tmpfs /run
    
    cj::path::bind_all
    
    # mise
    [[ -d ~/.local/share/mise ]] && cj::ro_bind ~/.local/share/mise
    [[ -d ~/.config/mise ]] && cj::ro_bind ~/.config/mise
    
    # cargo/rust
    [[ -d ~/.cargo ]] && cj::ro_bind ~/.cargo
    [[ -d ~/.rustup ]] && cj::ro_bind ~/.rustup
    
    # uv/python
    [[ -d ~/.cache/uv ]] && cj::ro_bind ~/.cache/uv
    [[ -d ~/.local/share/uv ]] && cj::ro_bind ~/.local/share/uv
    [[ -d ~/.pyenv ]] && cj::ro_bind ~/.pyenv
    
    # node
    [[ -d ~/.nvm ]] && cj::ro_bind ~/.nvm
    [[ -d ~/.npm ]] && cj::ro_bind ~/.npm
    [[ -d ~/.volta ]] && cj::ro_bind ~/.volta
    [[ -d ~/.bun ]] && cj::ro_bind ~/.bun
    
    # go
    [[ -d ~/go ]] && cj::ro_bind ~/go
    
    # general
    [[ -d ~/.local/bin ]] && cj::ro_bind ~/.local/bin
    
    cj::bind "$project_dir"
    cj::bind "$sandbox_home"
    
    cj::setenv HOME "$sandbox_home"
    cj::setenv XDG_CONFIG_HOME "$sandbox_home/.config"
    cj::setenv XDG_DATA_HOME "$sandbox_home/.local/share"
    cj::setenv XDG_CACHE_HOME "$sandbox_home/.cache"
    cj::setenv MISE_DATA_DIR ~/.local/share/mise
    cj::setenv MISE_CONFIG_DIR ~/.config/mise
    cj::setenv CARGO_HOME ~/.cargo
    cj::setenv RUSTUP_HOME ~/.rustup
    cj::setenv PATH "$PATH"
    cj::setenv TERM "${TERM:-xterm-256color}"
    cj::setenv LANG "${LANG:-en_US.UTF-8}"
    cj::setenv SHELL "/bin/bash"
}

cj::profile::register dev _cj_profile_dev
