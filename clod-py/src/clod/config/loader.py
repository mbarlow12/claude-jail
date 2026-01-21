"""Configuration file discovery and loading.

Discovers and loads TOML configuration files from user-level and
project-level locations, merging them with proper priority.
"""

import os
import tomllib
from pathlib import Path
from typing import Any

from clod.config.exceptions import (
    ConfigFileNotFoundError,
    DuplicateConfigError,
)
from clod.config.merge import deep_merge
from clod.config.settings import ClodSettings


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


def load_toml_file(path: Path) -> dict[str, Any]:
    """Load a TOML file and return its contents as a dict.

    Args:
        path: Path to the TOML file.

    Returns:
        Dictionary of configuration values.

    Raises:
        ConfigFileNotFoundError: If the file doesn't exist.
        tomllib.TOMLDecodeError: If the file contains invalid TOML.
    """
    if not path.is_file():
        raise ConfigFileNotFoundError(str(path))

    with open(path, "rb") as f:
        return tomllib.load(f)


def load_all_configs(
    project_dir: Path,
    explicit_config: Path | None = None,
) -> tuple[dict[str, Any], list[Path]]:
    """Load and merge all configuration files.

    When explicit_config is provided, ONLY that file is loaded (no merging).
    Otherwise, files are discovered and merged in priority order:
    1. User config (lowest)
    2. Project base config
    3. Project local config (highest)

    Args:
        project_dir: The project directory.
        explicit_config: Explicit config file path (--config option).
            If provided, only this file is used.

    Returns:
        Tuple of (merged_config_dict, list_of_loaded_files).

    Raises:
        ConfigFileNotFoundError: If explicit_config is provided but doesn't exist.
        DuplicateConfigError: If conflicting config files exist.
    """
    # Explicit config mode: load only the specified file
    if explicit_config is not None:
        config = load_toml_file(explicit_config)
        return config, [explicit_config]

    # Discovery mode: find and merge all configs
    loaded_files: list[Path] = []
    merged: dict[str, Any] = {}

    # 1. User config (lowest priority)
    user_config = discover_user_config()
    if user_config is not None:
        merged = deep_merge(merged, load_toml_file(user_config))
        loaded_files.append(user_config)

    # 2. Project configs
    base_config, local_config = discover_project_config(project_dir)

    if base_config is not None:
        merged = deep_merge(merged, load_toml_file(base_config))
        loaded_files.append(base_config)

    if local_config is not None:
        merged = deep_merge(merged, load_toml_file(local_config))
        loaded_files.append(local_config)

    return merged, loaded_files


def _get_env_prefix() -> str:
    """Get the environment variable prefix for ClodSettings."""
    return ClodSettings.model_config.get("env_prefix", "")


def _has_env_override(field_name: str) -> bool:
    """Check if an environment variable is set for a settings field.

    Args:
        field_name: The settings field name (e.g., "sandbox_name").

    Returns:
        True if the corresponding env var is set.
    """
    prefix = _get_env_prefix()
    env_var = f"{prefix}{field_name}".upper()
    return env_var in os.environ


def load_settings(
    project_dir: Path,
    explicit_config: Path | None = None,
) -> ClodSettings:
    """Load configuration files and return a ClodSettings object.

    This is the main entry point for loading configuration. It handles
    file discovery, loading, merging, and constructing the settings object.

    Environment variables take precedence over TOML values. This is achieved
    by excluding TOML keys that have corresponding env vars set, allowing
    Pydantic to read those values from the environment.

    Args:
        project_dir: The project directory.
        explicit_config: Explicit config file path (--config option).

    Returns:
        ClodSettings object with merged configuration.

    Raises:
        ConfigFileNotFoundError: If explicit_config doesn't exist.
        DuplicateConfigError: If conflicting config files exist.
    """
    config_dict, _ = load_all_configs(project_dir, explicit_config)

    # Remove keys that have env var overrides so Pydantic reads from env
    filtered_dict = {
        key: value
        for key, value in config_dict.items()
        if not _has_env_override(key)
    }

    return ClodSettings(**filtered_dict)
