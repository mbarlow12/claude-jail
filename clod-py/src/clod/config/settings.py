"""Settings for the clod sandbox environment.

Uses Pydantic v2 BaseSettings for environment variable support.
"""

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class ClodSettings(BaseSettings):
    """Settings for the sandbox environment.

    Settings are loaded from environment variables with the CLOD_ prefix.
    For example, CLOD_SANDBOX_NAME sets the sandbox_name field.
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
