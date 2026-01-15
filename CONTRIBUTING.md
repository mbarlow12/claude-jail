# Contributing to claude-jail

This guide covers development setup, testing, and how to extend claude-jail.

## Development Setup

### Dependencies

Install these packages for development and testing:

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y bubblewrap rsync shellcheck

# Arch
sudo pacman -S bubblewrap rsync shellcheck

# Fedora
sudo dnf install bubblewrap rsync ShellCheck
```

### Initialize Test Framework

The test suite uses [bats-core](https://github.com/bats-core/bats-core) with support and assert libraries as git submodules:

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/mbarlow12/claude-jail.git

# Or initialize submodules in existing clone
git submodule update --init --recursive
```

## Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run only unit tests
./tests/run_tests.sh unit

# Run only integration tests
./tests/run_tests.sh integration

# Run a specific test file
./tests/run_tests.sh tests/unit/bwrap.bats
```

### Test Structure

- `tests/unit/` - Unit tests for each `lib/*.sh` module
- `tests/integration/` - CLI and profile integration tests
- `tests/test_helper/common.bash` - Shared test utilities

### Manual Testing

```bash
# Debug: print bwrap command without running
claude-jail debug [dir] [profile]

# Interactive shell inside sandbox to verify mounts
claude-jail shell [dir] [profile]

# Verify isolation: these should fail inside sandbox
ls /home
cat ~/.ssh/id_rsa

# Clean sandbox to test fresh config copy
claude-jail clean [dir]
```

## Linting

Run ShellCheck on all source files before submitting:

```bash
shellcheck lib/*.sh bin/claude-jail profiles/*.sh
```

## Architecture

```
claude-jail/
├── bin/
│   └── claude-jail           # Standalone bash entry point
├── lib/
│   ├── bwrap.sh              # Core bwrap building blocks
│   ├── config.sh             # Configuration management
│   ├── profiles.sh           # Profile registration/loading
│   └── sandbox.sh            # Sandbox setup utilities
├── profiles/
│   ├── minimal.sh            # Fast, basic isolation
│   ├── standard.sh           # Balanced (default)
│   ├── dev.sh                # Developer toolchains
│   └── paranoid.sh           # Maximum isolation
├── tests/
│   ├── unit/                 # Unit tests for lib/*.sh
│   ├── integration/          # CLI and profile tests
│   └── run_tests.sh          # Test runner
└── claude-jail.plugin.zsh    # Zsh plugin (thin wrapper)
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

## Code Style

Use pure bash syntax only. Avoid zsh-specific features:

| Avoid (zsh) | Use (bash) |
|-------------|------------|
| `${var:h}` | `$(dirname "$var")` |
| `${(s/:/)var}` | `IFS=: read -ra array <<< "$var"` |
| `typeset -gA` | `declare -gA` |

## API Reference

### Core Functions (`lib/bwrap.sh`)

| Function | Description |
|----------|-------------|
| `cj::reset` | Clear all accumulated bwrap args |
| `cj::ro_bind <src> [dst]` | Read-only bind mount |
| `cj::bind <src> [dst]` | Read-write bind mount |
| `cj::tmpfs <path>` | Mount tmpfs |
| `cj::symlink <target> <link>` | Create symlink |
| `cj::proc [path]` | Mount /proc |
| `cj::dev [path]` | Mount /dev |
| `cj::setenv <name> <value>` | Set environment variable |
| `cj::unshare <ns...>` | Unshare namespaces (user, pid, net, ipc, uts, cgroup, all) |
| `cj::share <ns...>` | Share namespaces (net) |
| `cj::run <cmd...>` | Execute command in sandbox |

### System Helpers

| Function | Description |
|----------|-------------|
| `cj::system::base` | Bind /usr, /bin, /lib, /lib64 |
| `cj::system::dns` | Bind DNS config files |
| `cj::system::ssl` | Bind SSL certificates |
| `cj::system::users` | Bind passwd, group, localtime |
| `cj::path::bind_all` | Bind all directories in $PATH |
| `cj::path::find_real <name>` | Find and bind executable |

### Sandbox Helpers (`lib/sandbox.sh`)

| Function | Description |
|----------|-------------|
| `cj::sandbox::create_dirs <home>` | Create sandbox directory structure |
| `cj::sandbox::copy_claude_config <home>` | Copy ~/.claude to sandbox |
| `cj::sandbox::bind_credentials <home> <profile>` | Bind credentials for live sync |
| `cj::sandbox::init <project> <home> <profile>` | Full sandbox initialization |
| `cj::sandbox::chdir_path <project> <profile>` | Get working directory path for profile |
| `cj::sandbox::home_path <home> <profile>` | Get HOME path for profile display |
| `cj::sandbox::print_info <...>` | Print verbose startup information |
| `cj::sandbox::print_shell_info <home> <profile>` | Print shell entry information |

## CI/CD

The project uses GitHub Actions for automated testing. The workflow:
- Runs on push to main/master and on PRs
- Installs bubblewrap and rsync
- Runs unit and integration tests separately
- Runs ShellCheck on all shell scripts

See `.github/workflows/test.yml` for the full configuration.
