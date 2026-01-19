#!/usr/bin/env zsh
# clod.plugin.zsh - Zsh plugin for clod (minimal)
# Provides shell completions for the clod CLI

# Only load if clod is available
if (( ! $+commands[clod] )); then
    # Try to use uv run if clod isn't installed globally
    if (( $+commands[uv] )); then
        alias clod='uv run clod'
    else
        return 0
    fi
fi

# Enable Click shell completion for zsh
# Click supports completion via the _CLOD_COMPLETE environment variable
_clod_completion() {
    local -a completions
    local -a completions_with_descriptions
    local -a response
    (( ! $+commands[clod] )) && return 1

    response=("${(@f)$(env COMP_WORDS="${words[*]}" COMP_CWORD=$((CURRENT-1)) _CLOD_COMPLETE=zsh_complete clod)}")

    for type key descr in ${response}; do
        if [[ "$type" == "plain" ]]; then
            if [[ "$descr" == "_" ]]; then
                completions+=("$key")
            else
                completions_with_descriptions+=("$key":"$descr")
            fi
        elif [[ "$type" == "dir" ]]; then
            _path_files -/
        elif [[ "$type" == "file" ]]; then
            _path_files -f
        fi
    done

    if [ -n "$completions_with_descriptions" ]; then
        _describe -V unsorted completions_with_descriptions -U
    fi

    if [ -n "$completions" ]; then
        compadd -U -V unsorted -a completions
    fi
}

# Register the completion function
compdef _clod_completion clod

# Optional: Add convenience function to quickly jail current directory
cj() {
    clod jail "$@"
}
