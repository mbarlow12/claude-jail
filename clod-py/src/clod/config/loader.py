"""Configuration file discovery.

Discovers TOML configuration files from user-level and project-level locations.
The actual loading and merging is handled by ClodTomlSettingsSource in sources.py.
"""

import os
from pathlib import Path

from clod.config.exceptions import DuplicateConfigError


def get_config_home() -> Path:
    """Get the clod config home directory.

    Priority:
    1. $CLOD_CONFIG_HOME if set
    2. $XDG_CONFIG_HOME/clod if XDG_CONFIG_HOME is set
    3. ~/.config/clod (default)

    Returns:
        Path to the clod config home directory.
    """
    # Check CLOD_CONFIG_HOME first
    if clod_config_home := os.environ.get("CLOD_CONFIG_HOME"):
        return Path(clod_config_home)

    # Check XDG_CONFIG_HOME
    if xdg_config_home := os.environ.get("XDG_CONFIG_HOME"):
        return Path(xdg_config_home) / "clod"

    # Default to ~/.config/clod
    return Path.home() / ".config" / "clod"


def discover_user_config() -> Path | None:
    """Discover user-level configuration file.

    Looks for config.toml in the clod config home directory.

    Returns:
        Path to user config file if it exists, None otherwise.
    """
    config_file = get_config_home() / "config.toml"
    if config_file.is_file():
        return config_file
    return None


def discover_project_config(project_dir: Path) -> tuple[Path | None, Path | None]:
    """Discover project-level configuration files.

    Looks for:
    - Base config: clod.toml OR .clod/config.toml (mutually exclusive)
    - Local config: clod.local.toml OR .clod/config.local.toml (mutually exclusive)

    Args:
        project_dir: The project directory to search in.

    Returns:
        Tuple of (base_config_path, local_config_path). Either may be None.

    Raises:
        DuplicateConfigError: If both formats exist at the same level.
    """
    # Check for base config
    clod_toml = project_dir / "clod.toml"
    dot_clod_config = project_dir / ".clod" / "config.toml"

    base_config: Path | None = None
    if clod_toml.is_file() and dot_clod_config.is_file():
        raise DuplicateConfigError([str(clod_toml), str(dot_clod_config)])
    elif clod_toml.is_file():
        base_config = clod_toml
    elif dot_clod_config.is_file():
        base_config = dot_clod_config

    # Check for local config
    clod_local_toml = project_dir / "clod.local.toml"
    dot_clod_local = project_dir / ".clod" / "config.local.toml"

    local_config: Path | None = None
    if clod_local_toml.is_file() and dot_clod_local.is_file():
        raise DuplicateConfigError([str(clod_local_toml), str(dot_clod_local)])
    elif clod_local_toml.is_file():
        local_config = clod_local_toml
    elif dot_clod_local.is_file():
        local_config = dot_clod_local

    return base_config, local_config
