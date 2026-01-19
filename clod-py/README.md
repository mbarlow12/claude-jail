# clod

Minimal bubblewrap sandbox CLI for Claude Code - Python edition.

## Overview

`clod` is a Python package that provides a CLI for running Claude Code inside a bubblewrap (bwrap) sandbox. This is a minimal implementation based on the dev profile from [claude-jail](https://github.com/mbarlow12/claude-jail), rewritten in Python.

**Key Features:**
- Sandboxed execution with isolated home directory
- Development toolchain access (mise, cargo, uv, node version managers, etc.)
- Network access (configurable)
- Simple CLI using Click

## Installation

Using uv (recommended):

```bash
uv pip install clod
```

Or install from source:

```bash
git clone <repository>
cd clod-py
uv sync
```

## Usage

Basic usage:

```bash
# Run in current directory
clod jail

# Run in specific directory
clod jail -d ~/myproject

# Disable network access
clod jail --no-network

# Show sandbox info
clod jail -v

# Pass arguments to claude
clod jail -- --help
```

## How It Works

The `clod jail` command:

1. Creates a `.claude-sandbox` directory in your project
2. Builds a bubblewrap command with:
   - Unshared namespaces (user, pid, uts, ipc, cgroup)
   - Read-only system directories (/usr, /etc, etc.)
   - Read-only toolchain directories (~/.cargo, ~/.rustup, etc.)
   - Read-write project and sandbox directories
3. Runs `claude` inside the sandbox

The sandbox protects your real home directory while giving Claude access to development tools.

## Configuration

Environment variables:

- `CLOD_SANDBOX_NAME` - Sandbox directory name (default: `.claude-sandbox`)
- `CLOD_ENABLE_NETWORK` - Enable network (default: `true`)
- `CLOD_TERM` - TERM environment variable (default: `xterm-256color`)
- `CLOD_LANG` - LANG environment variable (default: `en_US.UTF-8`)
- `CLOD_SHELL` - SHELL environment variable (default: `/bin/bash`)

## Requirements

- Python >= 3.12
- bubblewrap (`sudo apt install bubblewrap`)
- claude CLI (`npm install -g @anthropics/claude-code`)

## Limitations

This is a minimal implementation that:

- Only implements the dev profile
- No profile selection
- No configuration file support
- No testing included
- Current directory only (no flexible sandbox location)

For full features, see the original [claude-jail](https://github.com/mbarlow12/claude-jail) bash implementation.

## License

MIT