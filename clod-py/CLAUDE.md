# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Python `clod` package.

## Overview

`clod` is a Python CLI for running Claude Code inside a bubblewrap sandbox. This is a minimal implementation that will eventually become the primary interface, with the bash implementation (`../bin/claude-jail`) being deprecated.

**Goal**: Full-featured Python CLI with a thin zsh wrapper for aliases and completions.

## Architecture

```
src/clod/
  cli.py       # Click-based CLI - 'clod jail' command
  bwrap.py     # BwrapBuilder class - constructs bwrap argument lists
  config.py    # Pydantic settings - environment-based configuration
  sandbox.py   # Sandbox initialization and dev profile logic
clod.plugin.zsh # Zsh plugin (completions + 'cj' alias)
```

### Key Components

**BwrapBuilder** (`bwrap.py`): Builder pattern for constructing bwrap commands. Mirrors the bash `cj::*` primitives:
- `ro_bind(src, dst)` / `bind(src, dst)` - Mount directories
- `system_base()` / `system_dns()` / `system_ssl()` / `system_users()` - System mounts
- `bind_path_dirs()` - Bind all PATH directories
- `unshare(*namespaces)` / `share(*namespaces)` - Namespace control
- `build()` - Returns final `["bwrap", ...]` command list

**SandboxSettings** (`config.py`): Pydantic BaseSettings with `CLOD_` env prefix:
- `sandbox_name` - Directory name (default: `.claude-sandbox`)
- `enable_network` - Network access (default: `true`)
- `term`, `lang`, `shell` - Environment variables

**Dev Profile** (`sandbox.py`): The `apply_dev_profile()` function implements the dev profile:
- Unshares user, pid, uts, ipc, cgroup namespaces
- Mounts system directories, toolchains (mise, cargo, uv, node managers, go)
- Sets up XDG directories and passes through git/proxy/API key env vars

## Development

```bash
# Install dependencies
uv sync

# Run the CLI
uv run clod jail
uv run clod jail -d ~/project
uv run clod jail --no-network
uv run clod jail -v  # Verbose output

# Type checking
uv run ty check src/

# Formatting
uv run ruff format src/
uv run ruff check src/
```

## Configuration

Environment variables (prefix: `CLOD_`):
- `CLOD_SANDBOX_NAME` - Sandbox directory name
- `CLOD_ENABLE_NETWORK` - Enable/disable network
- `CLOD_TERM`, `CLOD_LANG`, `CLOD_SHELL` - Terminal settings

## Current Limitations

- Only implements dev profile (no profile selection)
- No configuration file support
- No git worktree detection
- No tests yet

## Future Work

- Profile selection (`-p/--profile`)
- Configuration file support (TOML format)
- Git worktree auto-detection
- Test suite
- Replace bash implementation as primary interface
