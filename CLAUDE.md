# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

claude-jail is a shell-agnostic tool that runs Claude Code inside a bubblewrap (bwrap) sandbox to isolate it from the user's real home directory. This prevents accidental or malicious file access, deletion, or exfiltration.

**Core**: Pure bash library that works with any shell
**Interfaces**: Standalone script (`bin/claude-jail`) + optional Zsh plugin wrapper

## Architecture

```
bin/
  claude-jail              # Standalone bash entry point (main interface)
lib/
  bwrap.sh                 # Core bwrap primitives (pure bash)
  config.sh                # Environment + config file based configuration
  profiles.sh              # Profile registration and loading (pure bash)
  sandbox.sh               # Sandbox setup utilities (pure bash)
profiles/
  minimal.sh               # Basic isolation, mounts /etc read-only
  standard.sh              # Balanced (default) - selective /etc, preserves PATH
  paranoid.sh              # Maximum isolation - remaps paths to /work and /sandbox
  dev.sh                   # Toolchain-aware - binds mise, cargo, nvm, etc.
tests/
  test_helper/             # Bats-core framework and helpers
  unit/                    # Unit tests for lib/*.sh
  integration/             # Integration tests for CLI and profiles
claude-jail.plugin.zsh     # Optional: Zsh plugin (thin wrapper + completion)
```

### Key Design Patterns

**Pure bash core**: All `lib/*.sh` and `profiles/*.sh` files use bash-compatible syntax, no zsh-isms.

**Global state arrays** accumulate bwrap arguments:
- `_CJ_NS` - namespace flags (--unshare-*, --share-*)
- `_CJ_PRE` - directory creation (--dir)
- `_CJ_BINDS` - bind mounts, tmpfs, symlinks
- `_CJ_ENV` - environment variables
- `_CJ_SEEN` - deduplication map

**Profile functions** receive `(project_dir, sandbox_home)` and build the bwrap command by calling `cj::*` primitives. Register with `cj::profile::register <name> <function>`.

**Sandbox home** lives at `$project_dir/.claude-sandbox/` (configurable). Claude's `~/.claude` config is copied there on first run.

**Configuration layers** (highest to lowest priority):
1. CLI arguments (`--profile`, `--ro`, etc.)
2. Environment variables (`CJ_PROFILE`, `CJ_EXTRA_RO`, etc.)
3. Config file (`./.claude-jail.conf`, `~/.config/claude-jail/config`)
4. Built-in defaults

## Usage

### Standalone (no zsh required)

```bash
# Run in current directory
./bin/claude-jail

# Run in specific directory with custom profile
./bin/claude-jail -d ~/myproject -p paranoid

# Add to PATH for easier access
export PATH="$PATH:/path/to/claude-jail/bin"
claude-jail -v  # Now available globally
```

### Zsh Plugin (Oh My Zsh users)

```bash
# In ~/.zshrc
plugins=(... claude-jail)

# Optional: Configure via zstyle (backward compatibility)
zstyle ':claude-jail:*' profile standard
zstyle ':claude-jail:paths' extra-ro /usr/local/libs

# Or via environment variables (preferred)
export CJ_PROFILE=standard
export CJ_EXTRA_RO="/usr/local/libs:/opt/tools"
```

### Configuration

Create `~/.config/claude-jail/config`:

```bash
CJ_PROFILE=standard
CJ_NETWORK=true
CJ_SANDBOX_HOME=.claude-sandbox
CJ_COPY_CLAUDE_CONFIG=true
CJ_EXTRA_RO=(/usr/local/mylib /opt/tools)
CJ_EXTRA_RW=(/tmp/scratch)
```

Or use environment variables:

```bash
export CJ_PROFILE=paranoid
export CJ_EXTRA_RO="/usr/local/mylib:/opt/tools"
export CJ_NETWORK=false
claude-jail -d ~/project
```

## Testing

### Automated Tests (bats-core)

```bash
# Initialize test submodules (first time only)
git submodule update --init --recursive

# Run all tests
./tests/run_tests.sh

# Run only unit tests
./tests/run_tests.sh unit

# Run only integration tests
./tests/run_tests.sh integration

# Run a specific test file
./tests/run_tests.sh tests/unit/bwrap.bats
```

Test structure:
- `tests/unit/` - Unit tests for each lib/*.sh module
- `tests/integration/` - CLI and profile integration tests
- `tests/test_helper/common.bash` - Shared test utilities

### Manual Testing

```bash
# Debug: print bwrap command without running
claude-jail debug [dir] [profile]
# or: ./bin/claude-jail debug [dir] [profile]

# Interactive shell inside sandbox to verify mounts
claude-jail shell [dir] [profile]
# or: ./bin/claude-jail shell [dir] [profile]

# Verify isolation: these should fail inside sandbox
ls /home
cat ~/.ssh/id_rsa

# Clean sandbox to test fresh config copy
claude-jail clean [dir]
# or: ./bin/claude-jail clean [dir]
```

## Creating Custom Profiles

Add `profiles/myprofile.sh`:

```bash
#!/usr/bin/env bash
# profiles/myprofile.sh - My custom isolation profile

_cj_profile_myprofile() {
    local project_dir="$1"
    local sandbox_home="$2"

    cj::unshare user pid
    cj::system::base
    cj::system::dns
    cj::system::ssl
    cj::proc
    cj::dev
    cj::tmpfs /tmp

    cj::bind "$project_dir"
    cj::bind "$sandbox_home"

    # Custom mounts here
    cj::ro_bind ~/my-tools

    cj::setenv HOME "$sandbox_home"
    cj::setenv PATH "$PATH"
}

cj::profile::register myprofile _cj_profile_myprofile
```

**Note**: Use pure bash syntax only. Avoid zsh-specific features like:
- `${var:h}` → use `$(dirname "$var")`
- `${(s/:/)var}` → use `IFS=: read -ra array <<< "$var"`
- `typeset -gA` → use `declare -gA`

## Core API (lib/bwrap.sh)

| Function | Purpose |
|----------|---------|
| `cj::reset` | Clear accumulated args (call before building new command) |
| `cj::ro_bind <src> [dst]` | Read-only bind mount |
| `cj::bind <src> [dst]` | Read-write bind mount |
| `cj::tmpfs <path>` | Mount tmpfs |
| `cj::symlink <target> <link>` | Create symlink |
| `cj::proc` / `cj::dev` | Mount /proc, /dev |
| `cj::setenv <name> <value>` | Set environment variable |
| `cj::unshare <ns...>` | Unshare namespaces (user, pid, net, ipc, uts, cgroup, all) |
| `cj::share <ns...>` | Share namespaces (net) |
| `cj::run <cmd...>` | Execute command in sandbox |
| `cj::system::base` | Bind /usr, /bin, /lib, /lib64, handle symlinks |
| `cj::system::dns` | Bind DNS config files |
| `cj::system::ssl` | Bind SSL certificates |
| `cj::path::bind_all` | Bind all directories in $PATH |

## Sandbox API (lib/sandbox.sh)

| Function | Purpose |
|----------|---------|
| `cj::sandbox::create_dirs <home>` | Create standard sandbox directory structure |
| `cj::sandbox::copy_claude_config <home>` | Copy ~/.claude to sandbox (if enabled) |
| `cj::sandbox::bind_credentials <home> <profile>` | Bind credentials file for live sync |
| `cj::sandbox::init <project> <home> <profile>` | Full sandbox initialization |
| `cj::sandbox::chdir_path <project> <profile>` | Get working directory path for profile |
| `cj::sandbox::home_path <home> <profile>` | Get HOME path for profile display |
| `cj::sandbox::print_info <...>` | Print verbose startup information |
| `cj::sandbox::print_shell_info <home> <profile>` | Print shell entry information |

## Development Setup (for Claude Code Web Sessions)

When starting a new development session, run these commands to set up the environment:

```bash
# Install dependencies (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y bubblewrap rsync shellcheck

# Initialize test submodules
git submodule update --init --recursive

# Verify setup by running tests
./tests/run_tests.sh
```

### CI/CD Integration

The project uses GitHub Actions for automated testing. The workflow:
- Runs on push to main/master and on PRs
- Installs bubblewrap and rsync
- Runs unit and integration tests separately
- Runs ShellCheck on all shell scripts

See `.github/workflows/test.yml` for the full configuration.
