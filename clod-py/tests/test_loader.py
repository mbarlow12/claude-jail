"""Tests for config/loader.py file discovery functions."""

from pathlib import Path

import pytest

from clod.config import (
    DuplicateConfigError,
    discover_project_config,
    discover_user_config,
    get_config_home,
)


class TestGetConfigHome:
    """Tests for get_config_home function."""

    def test_clod_config_home_env(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """CLOD_CONFIG_HOME takes precedence."""
        monkeypatch.setenv("CLOD_CONFIG_HOME", "/custom/clod/config")
        monkeypatch.setenv("XDG_CONFIG_HOME", "/xdg/config")
        assert get_config_home() == Path("/custom/clod/config")

    def test_xdg_config_home_fallback(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """XDG_CONFIG_HOME/clod is used when CLOD_CONFIG_HOME not set."""
        monkeypatch.delenv("CLOD_CONFIG_HOME", raising=False)
        monkeypatch.setenv("XDG_CONFIG_HOME", "/xdg/config")
        assert get_config_home() == Path("/xdg/config/clod")

    def test_default_fallback(
        self, monkeypatch: pytest.MonkeyPatch, mock_home: Path
    ) -> None:
        """Falls back to ~/.config/clod when no env vars set."""
        monkeypatch.delenv("CLOD_CONFIG_HOME", raising=False)
        monkeypatch.delenv("XDG_CONFIG_HOME", raising=False)
        assert get_config_home() == mock_home / ".config" / "clod"


class TestDiscoverUserConfig:
    """Tests for discover_user_config function."""

    def test_returns_path_when_exists(self, config_home: Path) -> None:
        """Returns path when config.toml exists in config home."""
        config_file = config_home / "config.toml"
        config_file.write_text('sandbox_name = ".custom"')
        result = discover_user_config()
        assert result == config_file

    def test_returns_none_when_missing(self, config_home: Path) -> None:
        """Returns None when config.toml doesn't exist."""
        result = discover_user_config()
        assert result is None

    def test_returns_none_when_directory(self, config_home: Path) -> None:
        """Returns None when config.toml is a directory."""
        (config_home / "config.toml").mkdir()
        result = discover_user_config()
        assert result is None


class TestDiscoverProjectConfig:
    """Tests for discover_project_config function."""

    def test_no_config_files(self, project_dir: Path) -> None:
        """Returns (None, None) when no config files exist."""
        base, local = discover_project_config(project_dir)
        assert base is None
        assert local is None

    def test_clod_toml_only(self, project_dir: Path) -> None:
        """Finds clod.toml when it's the only base config."""
        config = project_dir / "clod.toml"
        config.write_text('sandbox_name = ".test"')
        base, local = discover_project_config(project_dir)
        assert base == config
        assert local is None

    def test_dot_clod_config_only(self, project_dir: Path) -> None:
        """Finds .clod/config.toml when it's the only base config."""
        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        config = dot_clod / "config.toml"
        config.write_text('sandbox_name = ".test"')
        base, local = discover_project_config(project_dir)
        assert base == config
        assert local is None

    def test_duplicate_base_config_error(self, project_dir: Path) -> None:
        """Raises error when both base config formats exist."""
        (project_dir / "clod.toml").write_text("a = 1")
        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        (dot_clod / "config.toml").write_text("b = 2")

        with pytest.raises(DuplicateConfigError) as exc_info:
            discover_project_config(project_dir)

        assert "clod.toml" in str(exc_info.value)
        assert ".clod/config.toml" in str(exc_info.value)

    def test_clod_local_toml_only(self, project_dir: Path) -> None:
        """Finds clod.local.toml when it's the only local config."""
        config = project_dir / "clod.local.toml"
        config.write_text("enable_network = false")
        base, local = discover_project_config(project_dir)
        assert base is None
        assert local == config

    def test_dot_clod_local_config_only(self, project_dir: Path) -> None:
        """Finds .clod/config.local.toml when it's the only local config."""
        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        config = dot_clod / "config.local.toml"
        config.write_text("enable_network = false")
        base, local = discover_project_config(project_dir)
        assert base is None
        assert local == config

    def test_duplicate_local_config_error(self, project_dir: Path) -> None:
        """Raises error when both local config formats exist."""
        (project_dir / "clod.local.toml").write_text("a = 1")
        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        (dot_clod / "config.local.toml").write_text("b = 2")

        with pytest.raises(DuplicateConfigError) as exc_info:
            discover_project_config(project_dir)

        assert "clod.local.toml" in str(exc_info.value)
        assert ".clod/config.local.toml" in str(exc_info.value)

    def test_mixed_formats_allowed(self, project_dir: Path) -> None:
        """Different formats for base and local are allowed."""
        base = project_dir / "clod.toml"
        base.write_text('sandbox_name = ".test"')

        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        local = dot_clod / "config.local.toml"
        local.write_text("enable_network = false")

        base_result, local_result = discover_project_config(project_dir)
        assert base_result == base
        assert local_result == local

    def test_base_and_local_both_found(self, project_dir: Path) -> None:
        """Finds both base and local configs."""
        base = project_dir / "clod.toml"
        base.write_text('sandbox_name = ".test"')
        local = project_dir / "clod.local.toml"
        local.write_text("enable_network = false")

        base_result, local_result = discover_project_config(project_dir)
        assert base_result == base
        assert local_result == local
