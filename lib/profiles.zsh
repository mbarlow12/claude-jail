# lib/profiles.zsh - Profile management
# Profiles define isolation levels and mount configurations

typeset -gA _CJ_PROFILES=()

cj::profile::register() {
    local name="$1" fn="$2"
    _CJ_PROFILES[$name]="$fn"
}

cj::profile::list() {
    echo "${(k)_CJ_PROFILES[@]}"
}

cj::profile::exists() {
    local name="$1"
    [[ -n "${_CJ_PROFILES[$name]}" ]]
}

cj::profile::apply() {
    local name="$1"
    local project_dir="$2"
    local sandbox_home="$3"
    
    if [[ -z "${_CJ_PROFILES[$name]}" ]]; then
        echo "Unknown profile: $name" >&2
        echo "Available: ${(k)_CJ_PROFILES[@]}" >&2
        return 1
    fi
    
    ${_CJ_PROFILES[$name]} "$project_dir" "$sandbox_home"
}

cj::profile::load_all() {
    local profile_dir="${1:-${0:A:h:h}/profiles}"
    local f
    
    for f in "$profile_dir"/*.zsh(N); do
        source "$f"
    done
}
