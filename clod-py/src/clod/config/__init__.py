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
)
from clod.config.settings import (
    ClodSettings,
    SandboxSettings,
    clear_config_context,
    get_sandbox_home,
    set_config_context,
)
from clod.config.sources import ClodTomlSettingsSource

__all__ = [
    # Exceptions
    "ConfigError",
    "ConfigFileNotFoundError",
    "DuplicateConfigError",
    # Discovery (loader)
    "discover_project_config",
    "discover_user_config",
    "get_config_home",
    # Settings
    "ClodSettings",
    "SandboxSettings",
    "get_sandbox_home",
    "set_config_context",
    "clear_config_context",
    # Sources
    "ClodTomlSettingsSource",
]
