# lib/config.zsh - Configuration via zstyle
# Usage: zstyle ':claude-jail:<context>' <option> <value>

cj::config::get() {
    local context="$1" key="$2" default="$3"
    local value
    zstyle -s ":claude-jail:$context" "$key" value || value="$default"
    echo "$value"
}

cj::config::get_bool() {
    local context="$1" key="$2" default="$3"
    local value
    zstyle -b ":claude-jail:$context" "$key" value || value="$default"
    [[ "$value" == "yes" ]]
}

cj::config::get_array() {
    local context="$1" key="$2"
    local -a values
    zstyle -a ":claude-jail:$context" "$key" values
    echo "${values[@]}"
}

cj::config::init_defaults() {
    zstyle ':claude-jail:*' profile standard
    zstyle ':claude-jail:*' network true
    zstyle ':claude-jail:*' sandbox-home .claude-sandbox
    zstyle ':claude-jail:*' copy-claude-config true
    zstyle ':claude-jail:*' verbose false
    
    zstyle ':claude-jail:paths' extra-ro ''
    zstyle ':claude-jail:paths' extra-rw ''
    zstyle ':claude-jail:paths' blocked ''
}

cj::config::show() {
    echo "claude-jail configuration:"
    echo "  profile:           $(cj::config::get '*' profile)"
    echo "  network:           $(cj::config::get '*' network)"
    echo "  sandbox-home:      $(cj::config::get '*' sandbox-home)"
    echo "  copy-claude-config: $(cj::config::get '*' copy-claude-config)"
    echo "  verbose:           $(cj::config::get '*' verbose)"
    echo ""
    echo "Extra paths:"
    echo "  read-only:  $(cj::config::get 'paths' extra-ro)"
    echo "  read-write: $(cj::config::get 'paths' extra-rw)"
}

cj::config::init_defaults
