"""Settings for the clod sandbox environment.

Uses Pydantic v2 BaseSettings with custom source ordering for TOML config support.
"""

from pathlib import Path
from typing import TYPE_CHECKING

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from .sources import ClodTomlSettingsSource

if TYPE_CHECKING:
    from pydantic_settings.sources import PydanticBaseSettingsSource

# Module-level state for passing context to settings_customise_sources
_project_dir: Path | None = None
_explicit_config: Path | None = None


def set_config_context(project_dir: Path, explicit_config: Path | None = None) -> None:
    """Set context for ClodSettings instantiation.

    This must be called before creating a ClodSettings instance to provide
    the project directory and optional explicit config file path for
    TOML config discovery.

    Args:
        project_dir: The project directory for config discovery.
        explicit_config: Explicit config file path (--config option).
    """
    global _project_dir, _explicit_config
    _project_dir = project_dir
    _explicit_config = explicit_config


def clear_config_context() -> None:
    """Clear the config context.

    This is primarily useful for testing to ensure a clean state.
    """
    global _project_dir, _explicit_config
    _project_dir = None
    _explicit_config = None


class ClodSettings(BaseSettings):
    """Settings for the sandbox environment.

    Settings are loaded from multiple sources with the following priority
    (highest to lowest):
    1. Constructor kwargs (init_settings)
    2. Environment variables with CLOD_ prefix (env_settings)
    3. TOML config files (merged from user/project/local configs)
    4. Field defaults
    """

    model_config = SettingsConfigDict(
        env_prefix="CLOD_",
        case_sensitive=False,
        extra="ignore",  # Ignore unknown keys in TOML files
    )

    # Sandbox location
    sandbox_name: str = Field(
        default=".claude-sandbox",
        description="Name of the sandbox directory",
    )

    # Network settings
    enable_network: bool = Field(
        default=True,
        description="Enable network access in sandbox",
    )

    # Environment
    term: str = Field(
        default="xterm-256color",
        description="TERM environment variable",
    )

    lang: str = Field(
        default="en_US.UTF-8",
        description="LANG environment variable",
    )

    shell: str = Field(
        default="/bin/bash",
        description="SHELL environment variable",
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: "PydanticBaseSettingsSource",
        env_settings: "PydanticBaseSettingsSource",
        dotenv_settings: "PydanticBaseSettingsSource",
        file_secret_settings: "PydanticBaseSettingsSource",
    ) -> tuple["PydanticBaseSettingsSource", ...]:
        """Customize settings sources and their priority.

        Priority order (first = highest):
        1. init_settings - Constructor kwargs
        2. env_settings - CLOD_* environment variables
        3. toml_source - Merged TOML config files

        This allows env vars to properly override TOML values without
        the manual filtering hack we had before.
        """
        global _project_dir, _explicit_config

        # Use current working directory as fallback if context not set
        project_dir = _project_dir if _project_dir is not None else Path.cwd()

        toml_source = ClodTomlSettingsSource(
            settings_cls,
            project_dir=project_dir,
            explicit_config=_explicit_config,
        )

        return (init_settings, env_settings, toml_source)


def get_sandbox_home(project_dir: Path, settings: ClodSettings) -> Path:
    """Get the sandbox home directory path.

    Args:
        project_dir: The project directory.
        settings: Sandbox settings.

    Returns:
        Path to the sandbox home directory.
    """
    return project_dir / settings.sandbox_name


# Backward compatibility alias
SandboxSettings = ClodSettings
