"""Configuration exceptions for clod."""


class ConfigError(Exception):
    """Base exception for configuration errors."""

    pass


class DuplicateConfigError(ConfigError):
    """Raised when conflicting config files exist at the same level.

    For example, if both `clod.toml` and `.clod/config.toml` exist in
    the same project directory.
    """

    def __init__(self, files: list[str]) -> None:
        self.files = files
        super().__init__(
            f"Conflicting config files found: {', '.join(files)}. "
            "Only one should exist."
        )


class ConfigFileNotFoundError(ConfigError):
    """Raised when an explicitly specified config file is not found."""

    def __init__(self, path: str) -> None:
        self.path = path
        super().__init__(f"Config file not found: {path}")
