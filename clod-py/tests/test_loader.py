"""Tests for config/loader.py file discovery and loading."""

from pathlib import Path

import pytest

from clod.config import (
    ClodSettings,
    ConfigFileNotFoundError,
    DuplicateConfigError,
    discover_project_config,
    discover_user_config,
    get_config_home,
    load_all_configs,
    load_settings,
    load_toml_file,
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


class TestLoadTomlFile:
    """Tests for load_toml_file function."""

    def test_loads_valid_toml(self, tmp_path: Path) -> None:
        """Loads valid TOML file."""
        config = tmp_path / "config.toml"
        config.write_text("""
sandbox_name = ".custom"
enable_network = false

[nested]
key = "value"
""")
        result = load_toml_file(config)
        assert result == {
            "sandbox_name": ".custom",
            "enable_network": False,
            "nested": {"key": "value"},
        }

    def test_file_not_found_error(self, tmp_path: Path) -> None:
        """Raises ConfigFileNotFoundError for missing file."""
        missing = tmp_path / "missing.toml"
        with pytest.raises(ConfigFileNotFoundError) as exc_info:
            load_toml_file(missing)
        assert str(missing) in str(exc_info.value)

    def test_invalid_toml_error(self, tmp_path: Path) -> None:
        """Raises TOMLDecodeError for invalid TOML."""
        import tomllib

        invalid = tmp_path / "invalid.toml"
        invalid.write_text("this is not valid toml [")
        with pytest.raises(tomllib.TOMLDecodeError):
            load_toml_file(invalid)


class TestLoadAllConfigs:
    """Tests for load_all_configs function."""

    def test_no_configs_returns_empty(self, project_dir: Path, clean_env: None) -> None:
        """Returns empty dict when no config files exist."""
        config, files = load_all_configs(project_dir)
        assert config == {}
        assert files == []

    def test_user_config_only(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Loads user config when it's the only one."""
        user_config = config_home / "config.toml"
        user_config.write_text('sandbox_name = ".user"')

        config, files = load_all_configs(project_dir)
        assert config == {"sandbox_name": ".user"}
        assert files == [user_config]

    def test_project_config_only(self, project_dir: Path, clean_env: None) -> None:
        """Loads project config when it's the only one."""
        proj_config = project_dir / "clod.toml"
        proj_config.write_text('sandbox_name = ".project"')

        config, files = load_all_configs(project_dir)
        assert config == {"sandbox_name": ".project"}
        assert files == [proj_config]

    def test_local_config_only(self, project_dir: Path, clean_env: None) -> None:
        """Loads local config when it's the only one."""
        local_config = project_dir / "clod.local.toml"
        local_config.write_text('sandbox_name = ".local"')

        config, files = load_all_configs(project_dir)
        assert config == {"sandbox_name": ".local"}
        assert files == [local_config]

    def test_merge_priority_order(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Later configs override earlier ones."""
        # User config (lowest priority)
        user_config = config_home / "config.toml"
        user_config.write_text("""
sandbox_name = ".user"
term = "from-user"
lang = "user-lang"
""")

        # Project base config
        proj_config = project_dir / "clod.toml"
        proj_config.write_text("""
sandbox_name = ".project"
term = "from-project"
""")

        # Project local config (highest priority)
        local_config = project_dir / "clod.local.toml"
        local_config.write_text('sandbox_name = ".local"')

        config, files = load_all_configs(project_dir)

        # Local overrides project overrides user
        assert config["sandbox_name"] == ".local"
        # Project overrides user
        assert config["term"] == "from-project"
        # User value preserved when not overridden
        assert config["lang"] == "user-lang"

        assert files == [user_config, proj_config, local_config]

    def test_explicit_config_only_mode(
        self, project_dir: Path, config_home: Path, tmp_path: Path, clean_env: None
    ) -> None:
        """Explicit config ignores all discovery."""
        # Create user and project configs that should be ignored
        user_config = config_home / "config.toml"
        user_config.write_text('sandbox_name = ".user"')
        proj_config = project_dir / "clod.toml"
        proj_config.write_text('sandbox_name = ".project"')

        # Explicit config
        explicit = tmp_path / "explicit.toml"
        explicit.write_text('sandbox_name = ".explicit"')

        config, files = load_all_configs(project_dir, explicit_config=explicit)
        assert config == {"sandbox_name": ".explicit"}
        assert files == [explicit]

    def test_explicit_config_not_found(
        self, project_dir: Path, tmp_path: Path, clean_env: None
    ) -> None:
        """Raises error when explicit config doesn't exist."""
        missing = tmp_path / "missing.toml"
        with pytest.raises(ConfigFileNotFoundError):
            load_all_configs(project_dir, explicit_config=missing)

    def test_nested_dict_merge(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Nested dicts are merged recursively."""
        user_config = config_home / "config.toml"
        user_config.write_text("""
[env]
TERM = "xterm"
LANG = "C"
""")

        proj_config = project_dir / "clod.toml"
        proj_config.write_text("""
[env]
LANG = "en_US.UTF-8"
SHELL = "/bin/bash"
""")

        config, _ = load_all_configs(project_dir)
        assert config["env"] == {
            "TERM": "xterm",
            "LANG": "en_US.UTF-8",
            "SHELL": "/bin/bash",
        }

    def test_list_replacement(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Lists are replaced entirely (not concatenated)."""
        user_config = config_home / "config.toml"
        user_config.write_text('extra_ro = ["/usr/local", "/opt"]')

        proj_config = project_dir / "clod.toml"
        proj_config.write_text('extra_ro = ["/custom/path"]')

        config, _ = load_all_configs(project_dir)
        assert config["extra_ro"] == ["/custom/path"]


class TestLoadSettings:
    """Tests for load_settings convenience function."""

    def test_returns_clod_settings(self, project_dir: Path, clean_env: None) -> None:
        """Returns a ClodSettings object."""
        result = load_settings(project_dir)
        assert isinstance(result, ClodSettings)

    def test_applies_toml_values(self, project_dir: Path, clean_env: None) -> None:
        """TOML values are applied to settings."""
        config = project_dir / "clod.toml"
        config.write_text("""
sandbox_name = ".from-toml"
enable_network = false
""")

        settings = load_settings(project_dir)
        assert settings.sandbox_name == ".from-toml"
        assert settings.enable_network is False

    def test_env_overrides_toml(
        self, project_dir: Path, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Environment variables override TOML values."""
        config = project_dir / "clod.toml"
        config.write_text('sandbox_name = ".from-toml"')

        monkeypatch.setenv("CLOD_SANDBOX_NAME", ".from-env")

        settings = load_settings(project_dir)
        assert settings.sandbox_name == ".from-env"

    def test_explicit_config(self, project_dir: Path, tmp_path: Path, clean_env: None) -> None:
        """Explicit config is used when provided."""
        explicit = tmp_path / "custom.toml"
        explicit.write_text('sandbox_name = ".explicit"')

        settings = load_settings(project_dir, explicit_config=explicit)
        assert settings.sandbox_name == ".explicit"

    def test_unknown_keys_ignored(self, project_dir: Path, clean_env: None) -> None:
        """Unknown keys in TOML are ignored (no error)."""
        config = project_dir / "clod.toml"
        config.write_text("""
sandbox_name = ".valid"
unknown_key = "should be ignored"
future_field = true
""")

        settings = load_settings(project_dir)
        assert settings.sandbox_name == ".valid"
        # No error raised, defaults used for fields not in TOML
        assert settings.enable_network is True
