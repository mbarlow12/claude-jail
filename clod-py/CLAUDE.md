# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Python `clod` package.

## Overview

`clod` is a Python CLI for running Claude Code inside a bubblewrap sandbox. This is a minimal implementation that will eventually become the primary interface, with the bash implementation (`../bin/claude-jail`) being deprecated.

**Goal**: Full-featured Python CLI with a thin zsh wrapper for aliases and completions.

## Architecture

```
src/clod/
  cli.py           # Click-based CLI - 'clod init' and 'clod jail' commands
  bwrap.py         # BwrapBuilder class - constructs bwrap argument lists
  sandbox.py       # Sandbox initialization and dev profile logic
  config/
    __init__.py    # Public API exports
    exceptions.py  # ConfigError, DuplicateConfigError, ConfigFileNotFoundError
    loader.py      # File discovery (user/project/local config paths)
    settings.py    # ClodSettings Pydantic model + context management
    sources.py     # ClodTomlSettingsSource - pydantic-settings integration
tests/
  conftest.py      # Pytest fixtures
  test_*.py        # Test modules
clod.plugin.zsh    # Zsh plugin (completions + 'cj' alias)
```

### Key Components

**BwrapBuilder** (`bwrap.py`): Builder pattern for constructing bwrap commands. Mirrors the bash `cj::*` primitives:
- `ro_bind(src, dst)` / `bind(src, dst)` - Mount directories
- `system_base()` / `system_dns()` / `system_ssl()` / `system_users()` - System mounts
- `bind_path_dirs()` - Bind all PATH directories
- `unshare(*namespaces)` / `share(*namespaces)` - Namespace control
- `build()` - Returns final `["bwrap", ...]` command list

**ClodSettings** (`config/settings.py`): Pydantic BaseSettings with `CLOD_` env prefix:
- `sandbox_name` - Directory name (default: `.claude-sandbox`)
- `enable_network` - Network access (default: `true`)
- `term`, `lang`, `shell` - Environment variables
- `set_config_context(project_dir, explicit_config)` - Set context before instantiation
- Uses `settings_customise_sources()` for proper source priority

**Config Discovery** (`config/loader.py`): TOML configuration file discovery:
- `discover_user_config()` - Find user-level config
- `discover_project_config()` - Find project base and local configs
- `get_config_home()` - Resolve config home directory

**ClodTomlSettingsSource** (`config/sources.py`): pydantic-settings integration:
- Discovers and deep-merges TOML configs using pydantic's `deep_update`
- Integrates with `settings_customise_sources()` for proper priority ordering

**Dev Profile** (`sandbox.py`): The `apply_dev_profile()` function implements the dev profile:
- Unshares user, pid, uts, ipc, cgroup namespaces
- Mounts system directories, toolchains (mise, cargo, uv, node managers, go)
- Sets up XDG directories and passes through git/proxy/API key env vars

## Development

```bash
# Install dependencies
uv sync

# Initialize user config (interactive)
uv run clod init
uv run clod init -y        # Accept all defaults
uv run clod init --force   # Overwrite existing config

# Run the CLI
uv run clod jail
uv run clod jail -d ~/project
uv run clod jail --no-network
uv run clod jail -v  # Verbose output

# Run tests
uv run pytest tests/ -v

# Type checking
uv run ty check src/

# Formatting
uv run ruff format src/
uv run ruff check src/
```

## Configuration

### File Discovery & Priority

Configuration is loaded from multiple sources with the following priority (highest to lowest):

1. **Environment variables** (`CLOD_` prefix) - Always override other sources
2. **Explicit config** (`-c/--config`) - Uses ONLY the specified file, no merging
3. **Project local**: `clod.local.toml` OR `.clod/config.local.toml`
4. **Project base**: `clod.toml` OR `.clod/config.toml`
5. **User-level**: `$CLOD_CONFIG_HOME/config.toml` (or `~/.config/clod/config.toml`)

**Rules:**
- Error if both `clod.toml` AND `.clod/config.toml` exist in the same directory
- Error if both `clod.local.toml` AND `.clod/config.local.toml` exist
- Mixed combinations are allowed (e.g., `clod.toml` + `.clod/config.local.toml`)
- TOML files are deep-merged (nested dicts recursive, lists replace entirely)

### Config File Format

```toml
# clod.toml or ~/.config/clod/config.toml
sandbox_name = ".claude-sandbox"
enable_network = true
term = "xterm-256color"
lang = "en_US.UTF-8"
shell = "/bin/bash"
```

### Environment Variables

All settings can be overridden via environment variables with `CLOD_` prefix:

- `CLOD_SANDBOX_NAME` - Sandbox directory name
- `CLOD_ENABLE_NETWORK` - Enable/disable network (`true`/`false`)
- `CLOD_TERM` - TERM environment variable
- `CLOD_LANG` - LANG environment variable
- `CLOD_SHELL` - SHELL environment variable
- `CLOD_CONFIG_HOME` - Override config home directory (default: `~/.config/clod`)

### CLI Options

```bash
# Initialize user config (creates ~/.config/clod/config.toml)
clod init              # Interactive - prompts for each setting
clod init -y           # Accept all defaults without prompting
clod init --force      # Overwrite existing config file
clod init --force -y   # Overwrite with defaults, no prompts

# Use specific config file (skips all discovery)
clod -c myconfig.toml jail

# Run in specific project directory
clod -d ~/myproject jail

# Combine options
clod -c custom.toml -d ~/project jail -v
```

## Current Limitations

- Only implements dev profile (no profile selection)
- No git worktree detection

## Future Work

- Profile selection (`-p/--profile`)
- Git worktree auto-detection
- Replace bash implementation as primary interface
