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

**Sandbox home** lives at `$cwd/.claude-sandbox/` by default (configurable via `CJ_SANDBOX_HOME` and `CJ_SANDBOX_NAME`). Claude's `~/.claude` config is copied there on first run.

**Git worktree support**: Auto-detects git worktrees and binds the main `.git` directory, enabling full git operations from worktrees.

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
CJ_SANDBOX_HOME=/path/to/sandboxes  # Parent directory for sandbox (default: cwd)
CJ_SANDBOX_NAME=.claude-sandbox     # Sandbox directory name
CJ_COPY_CLAUDE_CONFIG=true
CJ_GIT_WORKTREE_RO=false            # Bind main .git read-only in worktrees
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

### Git Worktree Support

claude-jail auto-detects git worktrees and binds the main `.git` directory:

```bash
# Layout:
# bean-barn/
#   main/        <- primary clone
#   feat-branch/ <- worktree

cd bean-barn
claude-jail -d feat-branch   # Auto-binds main/.git
claude-jail -d main          # .git is part of project, no extra binding

# Manual override if auto-detection fails
claude-jail -d feat-branch --git-root ./main

# Read-only for extra safety (limits some git operations)
claude-jail -d feat-branch --git-ro
```

### Sandbox Location

By default, sandbox is created at `$cwd/.claude-sandbox`. This enables sharing sandboxes between worktrees:

```bash
cd bean-barn
claude-jail -d main          # Sandbox: bean-barn/.claude-sandbox
claude-jail -d feat-branch   # Same sandbox (shared state)

# Override sandbox location
claude-jail --sandbox-home /tmp --sandbox-name my-sandbox
```

## Testing

```bash
# Run all tests
./tests/run_tests.sh

# Run only unit tests
./tests/run_tests.sh unit

# Run only integration tests
./tests/run_tests.sh integration
```

## Development Setup (for Claude Code Web Sessions)

**Important**: Before starting work, ensure your branch is up to date with `main`:

```bash
git fetch origin main
git merge origin/main
```

Do this periodically during longer sessions to avoid conflicts.

Quick setup for new development sessions:

```bash
# Install dependencies (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y bubblewrap rsync shellcheck

# Initialize test submodules
git submodule update --init --recursive

# Verify setup by running tests
./tests/run_tests.sh
```

For full development documentation including API reference, creating custom profiles, and code style guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).
