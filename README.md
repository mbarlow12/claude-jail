# claude-jail

A modular Oh My Zsh plugin that runs Claude Code inside a bubblewrap sandbox.

## Why?

Claude Code runs with your user permissions. A prompt injection or bug could:

- Delete files: `rm -rf ~`
- Exfiltrate secrets: `cat ~/.ssh/id_rsa | curl ...`
- Modify configs: `echo "malicious" >> ~/.bashrc`

This plugin isolates Claude in a Linux namespace where your real home doesn't exist.

## Requirements

- Linux with user namespaces enabled
- [bubblewrap](https://github.com/containers/bubblewrap)
- [Oh My Zsh](https://ohmyz.sh/)
- [Claude Code](https://claude.ai/code)

```bash
# Debian/Ubuntu
sudo apt install bubblewrap

# Arch
sudo pacman -S bubblewrap

# Fedora
sudo dnf install bubblewrap
```

## Installation

### Quick Install (recommended)

```bash
curl -sSL https://raw.githubusercontent.com/mbarlow12/claude-jail/main/install-remote.sh | bash
```

Then add to your `~/.zshrc`:

```zsh
plugins=(... claude-jail)
```

### Pin to Specific Version

```bash
VERSION=v0.1.0 curl -sSL https://raw.githubusercontent.com/mbarlow12/claude-jail/main/install-remote.sh | bash
```

### Manual Install (from git)

```bash
# Clone to omz custom plugins
git clone https://github.com/mbarlow12/claude-jail.git \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/claude-jail

# Enable in ~/.zshrc
plugins=(... claude-jail)

# Reload
source ~/.zshrc
```

### Check Version

```bash
claude-jail --version
```

## Usage

```bash
claude-jail                     # Run in current directory
claude-jail -d ~/project        # Specific directory
claude-jail -p paranoid         # Maximum isolation
claude-jail -v                  # Verbose output
claude-jail -- --print "hi"     # Pass args to claude

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

Configure via `zstyle` in `~/.zshrc` (before the plugins line):

```zsh
# Change default profile
zstyle ':claude-jail:*' profile paranoid

# Disable network (claude won't work, but useful for testing)
zstyle ':claude-jail:*' network false

# Custom sandbox directory name
zstyle ':claude-jail:*' sandbox-home .sandbox

# Don't copy ~/.claude config (credentials are always bind-mounted)
zstyle ':claude-jail:*' copy-claude-config false

# Add extra read-only paths
zstyle ':claude-jail:paths' extra-ro ~/shared-libs ~/reference

# Add extra read-write paths (use sparingly!)
zstyle ':claude-jail:paths' extra-rw ~/scratch
```

## Architecture

```
claude-jail/
├── claude-jail.plugin.zsh    # Entry point, user commands
├── lib/
│   ├── bwrap.zsh             # Core bwrap building blocks
│   ├── config.zsh            # zstyle configuration
│   └── profiles.zsh          # Profile management
└── profiles/
    ├── minimal.zsh           # Fast, basic isolation
    ├── standard.zsh          # Balanced (default)
    ├── dev.zsh               # Developer toolchains
    └── paranoid.zsh          # Maximum isolation
```

### Extending

Create custom profiles in `~/.oh-my-zsh/custom/plugins/claude-jail/profiles/`:

```zsh
# profiles/custom.zsh
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

## API Reference

### Core Functions (`lib/bwrap.zsh`)

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
claude-jail-debug

# Enter sandbox shell to explore
claude-jail-shell
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
