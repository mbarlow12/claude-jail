"""Configuration package for clod.

This package provides TOML-based configuration with layered discovery
and merging from user-level and project-level files.
"""

from clod.config.exceptions import (
    ConfigError,
    ConfigFileNotFoundError,
    DuplicateConfigError,
)
from clod.config.loader import (
    discover_project_config,
    discover_user_config,
    get_config_home,
    load_all_configs,
    load_settings,
    load_toml_file,
)
from clod.config.merge import deep_merge
from clod.config.settings import ClodSettings, SandboxSettings, get_sandbox_home

__all__ = [
    # Exceptions
    "ConfigError",
    "ConfigFileNotFoundError",
    "DuplicateConfigError",
    # Loader
    "discover_project_config",
    "discover_user_config",
    "get_config_home",
    "load_all_configs",
    "load_settings",
    "load_toml_file",
    # Utilities
    "deep_merge",
    # Settings
    "ClodSettings",
    "SandboxSettings",
    "get_sandbox_home",
]
