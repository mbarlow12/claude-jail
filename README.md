# claude-jail

A shell-agnostic tool that runs Claude Code inside a bubblewrap sandbox to isolate it from your real home directory.

## Why?

Claude Code runs with your user permissions. A prompt injection or bug could:

- Delete files: `rm -rf ~`
- Exfiltrate secrets: `cat ~/.ssh/id_rsa | curl ...`
- Modify configs: `echo "malicious" >> ~/.bashrc`

This tool isolates Claude in a Linux namespace where your real home doesn't exist.

## Requirements

- Linux with user namespaces enabled
- [bubblewrap](https://github.com/containers/bubblewrap)
- [Claude Code](https://claude.ai/code)
- (Optional) [Oh My Zsh](https://ohmyz.sh/) for zsh integration

```bash
# Debian/Ubuntu
sudo apt install bubblewrap

# Arch
sudo pacman -S bubblewrap

# Fedora
sudo dnf install bubblewrap
```

## Installation

### Standalone (works with any shell)

```bash
# Clone the repository
git clone https://github.com/mbarlow12/claude-jail.git
cd claude-jail

# Initialize test submodules (optional, for running tests)
git submodule update --init --recursive

# Add to PATH (add to your shell's rc file)
export PATH="$PATH:/path/to/claude-jail/bin"
```

### Oh My Zsh Plugin

```bash
# Clone to omz custom plugins
git clone https://github.com/mbarlow12/claude-jail.git \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/claude-jail

# Enable in ~/.zshrc
plugins=(... claude-jail)

# Reload
source ~/.zshrc
```

## Usage

### Standalone

```bash
claude-jail                     # Run in current directory
claude-jail -d ~/project        # Specific directory
claude-jail -p paranoid         # Maximum isolation
claude-jail -v                  # Verbose output
claude-jail -- --print "hi"     # Pass args to claude

claude-jail shell               # Test the sandbox interactively
claude-jail clean               # Remove .claude-sandbox/
claude-jail debug               # Print bwrap command
```

### Zsh Plugin

```bash
claude-jail                     # Run in current directory
claude-jail -d ~/project        # Specific directory
claude-jail -p paranoid         # Maximum isolation

claude-jail-shell               # Test the sandbox interactively
claude-jail-clean               # Remove .claude-sandbox/
claude-jail-debug               # Print bwrap command
```

## Profiles

| Profile | Isolation | Speed | Use Case |
|---------|-----------|-------|----------|
| `minimal` | Basic | Fast | Trusted code, quick iterations |
| `standard` | Balanced | Medium | Daily use (default) |
| `dev` | Balanced | Medium | Development with version managers (mise, cargo, nvm, etc.) |
| `paranoid` | Maximum | Slower | Untrusted code, security research |

### Profile Details

**minimal** (inspired by [akashakya's HN comment](https://news.ycombinator.com/item?id=45429787))

- Mounts `/etc` read-only (simple but exposes more)
- `--unshare-all --share-net`
- Fast startup

**standard** (inspired by [mfmayer's gist](https://gist.github.com/mfmayer/baf38e88d9e13d28f9484b546ede4bbd))

- Selective `/etc` (only dns, ssl, passwd)
- Preserves your `$PATH`
- Binds all PATH directories read-only

**dev**

- Same isolation as standard
- Binds version manager directories read-only: mise, cargo, rustup, nvm, pyenv, uv, volta, bun, go
- Best for projects using language version managers

**paranoid**

- Absolute minimum mounts
- Remaps paths: project → `/work`, home → `/sandbox`
- Minimal PATH: `/usr/local/bin:/usr/bin:/bin`

## Configuration

### Environment Variables (recommended)

```bash
export CJ_PROFILE=paranoid
export CJ_NETWORK=false
export CJ_SANDBOX_HOME=.claude-sandbox
export CJ_COPY_CLAUDE_CONFIG=true
export CJ_EXTRA_RO="/usr/local/mylib:/opt/tools"
export CJ_EXTRA_RW="/tmp/scratch"

claude-jail -d ~/project
```

### Config File

Create `~/.config/claude-jail/config` or `.claude-jail.conf` in your project:

```bash
CJ_PROFILE=standard
CJ_NETWORK=true
CJ_SANDBOX_HOME=.claude-sandbox
CJ_COPY_CLAUDE_CONFIG=true
CJ_EXTRA_RO=(/usr/local/mylib /opt/tools)
CJ_EXTRA_RW=(/tmp/scratch)
```

### Zsh zstyle (backward compatibility)

```zsh
# In ~/.zshrc (before the plugins line)
zstyle ':claude-jail:*' profile paranoid
zstyle ':claude-jail:*' network false
zstyle ':claude-jail:*' sandbox-home .sandbox
zstyle ':claude-jail:*' copy-claude-config false
zstyle ':claude-jail:paths' extra-ro ~/shared-libs ~/reference
zstyle ':claude-jail:paths' extra-rw ~/scratch
```

### Configuration Priority

1. CLI arguments (`--profile`, `--ro`, etc.)
2. Environment variables (`CJ_PROFILE`, `CJ_EXTRA_RO`, etc.)
3. Config file (`.claude-jail.conf`, `~/.config/claude-jail/config`)
4. Built-in defaults

## Development Setup

### Dependencies

For development and testing, install these additional packages:

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

### Running Tests

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

### Linting

```bash
# Run ShellCheck on all source files
shellcheck lib/*.sh bin/claude-jail profiles/*.sh
```

## Testing

### Automated Tests

```bash
# Initialize test submodules (first time only)
git submodule update --init --recursive

# Run all tests
./tests/run_tests.sh

# Run only unit tests
./tests/run_tests.sh unit

# Run only integration tests
./tests/run_tests.sh integration
```

### Manual Testing

```bash
# See what bwrap command would run
claude-jail debug

# Enter sandbox shell to explore
claude-jail shell
ls /home          # Should fail
echo $HOME        # Shows sandbox path
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

### Extending

Create custom profiles in `profiles/`:

```bash
#!/usr/bin/env bash
# profiles/custom.sh

_cj_profile_custom() {
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

    # Your custom mounts
    cj::ro_bind ~/my-tools

    cj::setenv HOME "$sandbox_home"
    cj::setenv PATH "$PATH"
}

cj::profile::register custom _cj_profile_custom
```

**Note**: Use pure bash syntax only. Avoid zsh-specific features.

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

## Troubleshooting

### "bwrap: No permissions to create new namespace"

Enable user namespaces:

```bash
sudo sysctl -w kernel.unprivileged_userns_clone=1
echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/userns.conf
```

### Claude can't authenticate

Credentials (`~/.claude/.credentials.json`) are bind-mounted into the sandbox, so authentication should work automatically. If you have issues:

```bash
# Verify credentials exist
ls -la ~/.claude/.credentials.json

# If missing, run claude outside the sandbox first to login
claude

# Then try claude-jail again
claude-jail
```

### Debug the sandbox

```bash
# See what bwrap command would run
claude-jail debug

# Enter sandbox shell to explore
claude-jail shell
ls /home          # Should fail
echo $HOME        # Shows sandbox path
```

## Security Notes

- Network access is enabled by default (required for Claude API)
- The sandbox protects against accidental damage, not determined attackers
- For higher security, use `--no-network` or run in a VM
- Consider [cco](https://github.com/nikvdp/cco) or Docker for additional isolation

## Credits

- [cco](https://github.com/nikvdp/cco) - Environment passthrough patterns, XDG config detection
- [mfmayer's gist](https://gist.github.com/mfmayer/baf38e88d9e13d28f9484b546ede4bbd) - Modular bwrap approach
- [akashakya's HN comment](https://news.ycombinator.com/item?id=45429787) - Minimal bwrap example

## License

MIT
