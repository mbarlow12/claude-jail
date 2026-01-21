"""Sandbox setup and management.

Implements the dev profile logic from claude-jail.
"""

import os
import shutil
from pathlib import Path

from clod.bwrap import BwrapBuilder
from clod.config import ClodSettings


def create_sandbox_dirs(sandbox_home: Path) -> None:
    """Create standard sandbox directory structure.

    Args:
        sandbox_home: Path to the sandbox home directory.
    """
    dirs = [
        sandbox_home / ".config",
        sandbox_home / ".cache",
        sandbox_home / ".local" / "share",
        sandbox_home / ".claude",
    ]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)


def copy_claude_config(sandbox_home: Path) -> None:
    """Copy Claude configuration from host to sandbox.

    Args:
        sandbox_home: Path to the sandbox home directory.
    """
    host_claude = Path.home() / ".claude"
    sandbox_claude = sandbox_home / ".claude"
    copied_marker = sandbox_claude / ".copied"

    # Copy ~/.claude directory if it exists and hasn't been copied
    if host_claude.is_dir() and not copied_marker.exists():
        # Use rsync-like behavior: copy contents, don't overwrite existing
        if shutil.which("rsync"):
            os.system(
                f"rsync -a --ignore-existing {host_claude}/ {sandbox_claude}/ 2>/dev/null"
            )
        else:
            # Fallback to manual copy
            for item in host_claude.iterdir():
                dest = sandbox_claude / item.name
                if not dest.exists():
                    if item.is_dir():
                        shutil.copytree(item, dest)
                    else:
                        shutil.copy2(item, dest)
        copied_marker.touch()

    # Copy ~/.claude.json if it exists
    host_claude_json = Path.home() / ".claude.json"
    sandbox_claude_json = sandbox_home / ".claude.json"
    if host_claude_json.is_file() and not sandbox_claude_json.exists():
        shutil.copy2(host_claude_json, sandbox_claude_json)


def bind_toolchain_dirs(builder: BwrapBuilder) -> None:
    """Bind tool-specific directories (mise, cargo, uv, node, etc.).

    Args:
        builder: BwrapBuilder instance to add bindings to.
    """
    home = Path.home()

    # mise
    if (home / ".local/share/mise").is_dir():
        builder.ro_bind(home / ".local/share/mise")
    if (home / ".config/mise").is_dir():
        builder.ro_bind(home / ".config/mise")

    # cargo/rust
    if (home / ".cargo").is_dir():
        builder.ro_bind(home / ".cargo")
    if (home / ".rustup").is_dir():
        builder.ro_bind(home / ".rustup")

    # uv/python
    if (home / ".cache/uv").is_dir():
        builder.ro_bind(home / ".cache/uv")
    if (home / ".local/share/uv").is_dir():
        builder.ro_bind(home / ".local/share/uv")
    if (home / ".pyenv").is_dir():
        builder.ro_bind(home / ".pyenv")

    # node
    if (home / ".nvm").is_dir():
        builder.ro_bind(home / ".nvm")
    if (home / ".npm").is_dir():
        builder.ro_bind(home / ".npm")
    if (home / ".volta").is_dir():
        builder.ro_bind(home / ".volta")
    if (home / ".bun").is_dir():
        builder.ro_bind(home / ".bun")

    # go
    if (home / "go").is_dir():
        builder.ro_bind(home / "go")

    # general
    if (home / ".local/bin").is_dir():
        builder.ro_bind(home / ".local/bin")


def setup_environment(
    builder: BwrapBuilder, sandbox_home: Path, settings: ClodSettings
) -> None:
    """Set up environment variables for the sandbox.

    Args:
        builder: BwrapBuilder instance.
        sandbox_home: Path to sandbox home directory.
        settings: Sandbox settings.
    """
    builder.setenv("HOME", str(sandbox_home))
    builder.setenv("XDG_CONFIG_HOME", str(sandbox_home / ".config"))
    builder.setenv("XDG_DATA_HOME", str(sandbox_home / ".local/share"))
    builder.setenv("XDG_CACHE_HOME", str(sandbox_home / ".cache"))

    # Tool-specific environment
    builder.setenv("MISE_DATA_DIR", str(Path.home() / ".local/share/mise"))
    builder.setenv("MISE_CONFIG_DIR", str(Path.home() / ".config/mise"))
    builder.setenv("CARGO_HOME", str(Path.home() / ".cargo"))
    builder.setenv("RUSTUP_HOME", str(Path.home() / ".rustup"))

    # System environment
    builder.setenv("PATH", os.environ.get("PATH", ""))
    builder.setenv("TERM", settings.term)
    builder.setenv("LANG", settings.lang)
    builder.setenv("SHELL", settings.shell)

    # Pass through git identity if set
    for var in [
        "GIT_AUTHOR_NAME",
        "GIT_AUTHOR_EMAIL",
        "GIT_COMMITTER_NAME",
        "GIT_COMMITTER_EMAIL",
    ]:
        if value := os.environ.get(var):
            builder.setenv(var, value)

    # Pass through proxy settings
    for var in [
        "http_proxy",
        "https_proxy",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "no_proxy",
        "NO_PROXY",
    ]:
        if value := os.environ.get(var):
            builder.setenv(var, value)

    # Pass through API key
    if api_key := os.environ.get("ANTHROPIC_API_KEY"):
        builder.setenv("ANTHROPIC_API_KEY", api_key)


def apply_dev_profile(
    builder: BwrapBuilder,
    project_dir: Path,
    sandbox_home: Path,
    settings: ClodSettings,
) -> None:
    """Apply the dev profile configuration.

    This is the core logic from profiles/dev.sh.

    Args:
        builder: BwrapBuilder instance.
        project_dir: Project directory to mount.
        sandbox_home: Sandbox home directory.
        settings: Sandbox settings.
    """
    # Unshare namespaces
    builder.unshare("user", "pid", "uts", "ipc", "cgroup")

    # System base
    builder.system_base()
    builder.system_dns()
    builder.system_ssl()
    builder.system_users()

    # /etc/alternatives
    if Path("/etc/alternatives").is_dir():
        builder.ro_bind("/etc/alternatives")

    # /proc and /dev
    builder.proc()
    builder.dev()

    # tmpfs mounts
    builder.tmpfs("/tmp")
    builder.tmpfs("/run")

    # Bind all PATH directories
    builder.bind_path_dirs()

    # Bind toolchain directories
    bind_toolchain_dirs(builder)

    # Bind project and sandbox
    builder.bind(project_dir)
    builder.bind(sandbox_home)

    # Set up environment
    setup_environment(builder, sandbox_home, settings)

    # Set working directory
    builder.chdir(str(project_dir))


def initialize_sandbox(
    project_dir: Path, sandbox_home: Path, settings: ClodSettings
) -> BwrapBuilder:
    """Initialize the sandbox and return a configured BwrapBuilder.

    Args:
        project_dir: Project directory.
        sandbox_home: Sandbox home directory.
        settings: Sandbox settings.

    Returns:
        Configured BwrapBuilder ready to build the command.
    """
    # Create sandbox directories
    create_sandbox_dirs(sandbox_home)

    # Copy Claude config
    copy_claude_config(sandbox_home)

    # Create and configure builder
    builder = BwrapBuilder()
    apply_dev_profile(builder, project_dir, sandbox_home, settings)

    return builder
