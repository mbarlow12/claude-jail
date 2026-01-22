"""Custom pydantic-settings source for clod's TOML configuration.

This module provides a settings source that integrates with pydantic-settings'
`settings_customise_sources()` to handle clod's layered TOML config discovery
and deep merging.
"""

import tomllib
from pathlib import Path
from typing import Any

from pydantic._internal._utils import deep_update
from pydantic_settings import BaseSettings
from pydantic_settings.sources import InitSettingsSource

from .exceptions import ConfigFileNotFoundError
from .loader import discover_project_config, discover_user_config


class ClodTomlSettingsSource(InitSettingsSource):
    """Settings source that loads from clod's TOML config hierarchy.

    This source discovers, loads, and deep-merges TOML config files
    from user-level and project-level locations.

    Priority order (lowest to highest):
    1. User config (~/.config/clod/config.toml)
    2. Project base config (clod.toml or .clod/config.toml)
    3. Project local config (clod.local.toml or .clod/config.local.toml)

    When explicit_config is provided, ONLY that file is used (no discovery).
    """

    def __init__(
        self,
        settings_cls: type[BaseSettings],
        project_dir: Path,
        explicit_config: Path | None = None,
    ) -> None:
        """Initialize the TOML settings source.

        Args:
            settings_cls: The pydantic-settings class.
            project_dir: The project directory for config discovery.
            explicit_config: Explicit config file path (--config option).
                If provided, only this file is used.
        """
        self.project_dir = project_dir
        self.explicit_config = explicit_config

        # Discover and load config files, then pass merged dict to InitSettingsSource
        toml_data = self._load_configs()
        super().__init__(settings_cls, toml_data)

    def _load_configs(self) -> dict[str, Any]:
        """Discover, load, and merge config files.

        Returns:
            Merged configuration dictionary.

        Raises:
            ConfigFileNotFoundError: If explicit_config doesn't exist.
            DuplicateConfigError: If conflicting config files exist.
        """
        if self.explicit_config:
            return self._load_toml(self.explicit_config, required=True)

        merged: dict[str, Any] = {}

        # Load in priority order (lowest to highest)
        # deep_update(base, override) -> override wins on conflicts
        if user_config := discover_user_config():
            merged = deep_update(merged, self._load_toml(user_config))

        base, local = discover_project_config(self.project_dir)
        if base:
            merged = deep_update(merged, self._load_toml(base))
        if local:
            merged = deep_update(merged, self._load_toml(local))

        return merged

    def _load_toml(self, path: Path, required: bool = False) -> dict[str, Any]:
        """Load a TOML file.

        Args:
            path: Path to the TOML file.
            required: If True, raise error when file doesn't exist.

        Returns:
            Dictionary of configuration values.

        Raises:
            ConfigFileNotFoundError: If required is True and file doesn't exist.
        """
        if not path.is_file():
            if required:
                raise ConfigFileNotFoundError(str(path))
            return {}

        with open(path, "rb") as f:
            return tomllib.load(f)
