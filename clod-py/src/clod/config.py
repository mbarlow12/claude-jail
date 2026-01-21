"""Configuration settings using Pydantic.

Placeholder for future configuration management.
"""

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings


class SandboxSettings(BaseSettings):
    """Settings for the sandbox environment."""

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

    class Config:
        """Pydantic configuration."""

        env_prefix: str = "CLOD_"
        case_sensitive: bool = False


def get_sandbox_home(project_dir: Path, settings: SandboxSettings) -> Path:
    """Get the sandbox home directory path.

    Args:
        project_dir: The project directory.
        settings: Sandbox settings.

    Returns:
        Path to the sandbox home directory.
    """
    return project_dir / settings.sandbox_name
