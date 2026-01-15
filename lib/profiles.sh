#!/usr/bin/env bash
# lib/profiles.sh - Profile management (pure bash)
# Profiles define isolation levels and mount configurations

declare -gA _CJ_PROFILES=()

cj::profile::register() {
    local name="$1" fn="$2"
    _CJ_PROFILES[$name]="$fn"
}

cj::profile::list() {
    # Print keys of associative array
    for profile in "${!_CJ_PROFILES[@]}"; do
        echo "$profile"
    done | sort
}

cj::profile::exists() {
    local name="$1"
    [[ -n "${_CJ_PROFILES[$name]:-}" ]]
}

cj::profile::apply() {
    local name="$1"
    local project_dir="$2"
    local sandbox_home="$3"

    if [[ -z "${_CJ_PROFILES[$name]:-}" ]]; then
        echo "Unknown profile: $name" >&2
        echo "Available: $(cj::profile::list | tr '\n' ' ')" >&2
        return 1
    fi

    ${_CJ_PROFILES[$name]} "$project_dir" "$sandbox_home"
}

cj::profile::load_all() {
    local profile_dir="$1"
    local f

    [[ ! -d "$profile_dir" ]] && return 0

    for f in "$profile_dir"/*.sh; do
        [[ ! -f "$f" ]] && continue
        # shellcheck disable=SC1090
        source "$f"
    done
}
