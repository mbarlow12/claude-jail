# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

claude-jail is an Oh My Zsh plugin that runs Claude Code inside a bubblewrap (bwrap) sandbox to isolate it from the user's real home directory. This prevents accidental or malicious file access, deletion, or exfiltration.

## Architecture

The plugin uses a modular architecture with composable bwrap building blocks:

```
claude-jail.plugin.zsh     # Entry point: user commands, CLI parsing
lib/
  bwrap.zsh                # Core bwrap primitives (cj::ro_bind, cj::bind, cj::run, etc.)
  config.zsh               # zstyle-based configuration system
  profiles.zsh             # Profile registration and loading
profiles/
  minimal.zsh              # Basic isolation, mounts /etc read-only
  standard.zsh             # Balanced (default) - selective /etc, preserves PATH
  paranoid.zsh             # Maximum isolation - remaps paths to /work and /sandbox
  dev.zsh                  # Toolchain-aware - binds mise, cargo, nvm, etc. read-only
```

### Key Design Patterns

**Global state arrays** accumulate bwrap arguments:
- `_CJ_NS` - namespace flags (--unshare-*, --share-*)
- `_CJ_PRE` - directory creation (--dir)
- `_CJ_BINDS` - bind mounts, tmpfs, symlinks
- `_CJ_ENV` - environment variables
- `_CJ_SEEN` - deduplication map

**Profile functions** receive `(project_dir, sandbox_home)` and build the bwrap command by calling `cj::*` primitives. Register with `cj::profile::register <name> <function>`.

**Sandbox home** lives at `$project_dir/.claude-sandbox/` (configurable). Claude's `~/.claude` config is copied there on first run.

## Testing Changes

```bash
# Debug: print bwrap command without running
claude-jail-debug [dir] [profile]

# Interactive shell inside sandbox to verify mounts
claude-jail-shell [dir] [profile]

# Verify isolation: these should fail inside sandbox
ls /home
cat ~/.ssh/id_rsa

# Clean sandbox to test fresh config copy
claude-jail-clean [dir]
```

## Creating Custom Profiles

Add `profiles/myprofile.zsh`:

```zsh
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

## Core API (lib/bwrap.zsh)

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
