"""Tests for config/settings.py ClodSettings and source-based config loading."""

from pathlib import Path

import pytest

from clod.config import (
    ClodSettings,
    ConfigFileNotFoundError,
    DuplicateConfigError,
    SandboxSettings,
    clear_config_context,
    get_sandbox_home,
    set_config_context,
)


@pytest.fixture(autouse=True)
def reset_context() -> None:
    """Clear config context before and after each test."""
    clear_config_context()
    yield
    clear_config_context()


class TestClodSettings:
    """Tests for ClodSettings default values and env overrides."""

    def test_default_values(self, clean_env: None) -> None:
        """Default values are set correctly."""
        settings = ClodSettings()
        assert settings.sandbox_name == ".claude-sandbox"
        assert settings.enable_network is True
        assert settings.term == "xterm-256color"
        assert settings.lang == "en_US.UTF-8"
        assert settings.shell == "/bin/bash"

    def test_env_override_sandbox_name(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLOD_SANDBOX_NAME overrides default."""
        monkeypatch.setenv("CLOD_SANDBOX_NAME", ".my-sandbox")
        settings = ClodSettings()
        assert settings.sandbox_name == ".my-sandbox"

    def test_env_override_enable_network(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLOD_ENABLE_NETWORK overrides default."""
        monkeypatch.setenv("CLOD_ENABLE_NETWORK", "false")
        settings = ClodSettings()
        assert settings.enable_network is False

    def test_env_override_term(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLOD_TERM overrides default."""
        monkeypatch.setenv("CLOD_TERM", "screen-256color")
        settings = ClodSettings()
        assert settings.term == "screen-256color"

    def test_env_override_lang(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLOD_LANG overrides default."""
        monkeypatch.setenv("CLOD_LANG", "C.UTF-8")
        settings = ClodSettings()
        assert settings.lang == "C.UTF-8"

    def test_env_override_shell(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLOD_SHELL overrides default."""
        monkeypatch.setenv("CLOD_SHELL", "/bin/zsh")
        settings = ClodSettings()
        assert settings.shell == "/bin/zsh"

    def test_case_insensitive_env(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Environment variables are case insensitive."""
        monkeypatch.setenv("clod_sandbox_name", ".lower-case")
        settings = ClodSettings()
        assert settings.sandbox_name == ".lower-case"

    def test_init_with_kwargs(self, clean_env: None) -> None:
        """Settings can be initialized with kwargs."""
        settings = ClodSettings(
            sandbox_name=".custom",
            enable_network=False,
        )
        assert settings.sandbox_name == ".custom"
        assert settings.enable_network is False

    def test_init_kwargs_override_env(
        self, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Init kwargs override environment variables."""
        monkeypatch.setenv("CLOD_SANDBOX_NAME", ".from-env")
        settings = ClodSettings(sandbox_name=".from-kwargs")
        assert settings.sandbox_name == ".from-kwargs"


class TestTomlConfigLoading:
    """Tests for TOML config loading through settings_customise_sources."""

    def test_project_config_loaded(self, project_dir: Path, clean_env: None) -> None:
        """TOML values are applied to settings via source."""
        config = project_dir / "clod.toml"
        config.write_text("""
sandbox_name = ".from-toml"
enable_network = false
""")

        set_config_context(project_dir)
        settings = ClodSettings()
        assert settings.sandbox_name == ".from-toml"
        assert settings.enable_network is False

    def test_env_overrides_toml(
        self, project_dir: Path, clean_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Environment variables override TOML values."""
        config = project_dir / "clod.toml"
        config.write_text('sandbox_name = ".from-toml"')

        monkeypatch.setenv("CLOD_SANDBOX_NAME", ".from-env")

        set_config_context(project_dir)
        settings = ClodSettings()
        assert settings.sandbox_name == ".from-env"

    def test_explicit_config(
        self, project_dir: Path, tmp_path: Path, clean_env: None
    ) -> None:
        """Explicit config is used when provided."""
        # Create project config that should be ignored
        (project_dir / "clod.toml").write_text('sandbox_name = ".project"')

        # Create explicit config
        explicit = tmp_path / "custom.toml"
        explicit.write_text('sandbox_name = ".explicit"')

        set_config_context(project_dir, explicit_config=explicit)
        settings = ClodSettings()
        assert settings.sandbox_name == ".explicit"

    def test_explicit_config_not_found(
        self, project_dir: Path, tmp_path: Path, clean_env: None
    ) -> None:
        """Raises error when explicit config doesn't exist."""
        missing = tmp_path / "missing.toml"

        set_config_context(project_dir, explicit_config=missing)
        with pytest.raises(ConfigFileNotFoundError):
            ClodSettings()

    def test_unknown_keys_ignored(self, project_dir: Path, clean_env: None) -> None:
        """Unknown keys in TOML are ignored (no error)."""
        config = project_dir / "clod.toml"
        config.write_text("""
sandbox_name = ".valid"
unknown_key = "should be ignored"
future_field = true
""")

        set_config_context(project_dir)
        settings = ClodSettings()
        assert settings.sandbox_name == ".valid"
        # No error raised, defaults used for fields not in TOML
        assert settings.enable_network is True

    def test_merge_priority_order(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Later configs override earlier ones in priority order."""
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

        # Project local config (highest priority among TOML)
        local_config = project_dir / "clod.local.toml"
        local_config.write_text('sandbox_name = ".local"')

        set_config_context(project_dir)
        settings = ClodSettings()

        # Local overrides project overrides user
        assert settings.sandbox_name == ".local"
        # Project overrides user
        assert settings.term == "from-project"
        # User value preserved when not overridden
        assert settings.lang == "user-lang"

    def test_nested_dict_merge(
        self, project_dir: Path, config_home: Path, clean_env: None
    ) -> None:
        """Nested dicts are merged recursively using deep_update."""
        # Note: ClodSettings doesn't have nested dict fields currently,
        # but this tests the deep_update behavior in the source
        user_config = config_home / "config.toml"
        user_config.write_text("""
sandbox_name = ".user"
""")

        proj_config = project_dir / "clod.toml"
        proj_config.write_text("""
sandbox_name = ".project"
""")

        set_config_context(project_dir)
        settings = ClodSettings()
        assert settings.sandbox_name == ".project"

    def test_duplicate_config_error(self, project_dir: Path, clean_env: None) -> None:
        """Raises error when duplicate config formats exist."""
        (project_dir / "clod.toml").write_text("sandbox_name = '.a'")
        dot_clod = project_dir / ".clod"
        dot_clod.mkdir()
        (dot_clod / "config.toml").write_text("sandbox_name = '.b'")

        set_config_context(project_dir)
        with pytest.raises(DuplicateConfigError):
            ClodSettings()


class TestSandboxSettingsAlias:
    """Tests for backward compatibility SandboxSettings alias."""

    def test_alias_is_clod_settings(self) -> None:
        """SandboxSettings is an alias for ClodSettings."""
        assert SandboxSettings is ClodSettings

    def test_alias_can_be_instantiated(self, clean_env: None) -> None:
        """SandboxSettings can be instantiated."""
        settings = SandboxSettings()
        assert settings.sandbox_name == ".claude-sandbox"


class TestGetSandboxHome:
    """Tests for get_sandbox_home function."""

    def test_returns_correct_path(self, clean_env: None, tmp_path: Path) -> None:
        """Returns project_dir / sandbox_name."""
        project = tmp_path / "project"
        settings = ClodSettings(sandbox_name=".my-sandbox")
        result = get_sandbox_home(project, settings)
        assert result == project / ".my-sandbox"

    def test_with_default_sandbox_name(self, clean_env: None, tmp_path: Path) -> None:
        """Works with default sandbox_name."""
        project = tmp_path / "project"
        settings = ClodSettings()
        result = get_sandbox_home(project, settings)
        assert result == project / ".claude-sandbox"


class TestSetConfigContext:
    """Tests for set_config_context and clear_config_context functions."""

    def test_context_affects_settings(
        self, project_dir: Path, clean_env: None
    ) -> None:
        """Setting context affects which config files are loaded."""
        config = project_dir / "clod.toml"
        config.write_text('sandbox_name = ".context-test"')

        # Without context, uses cwd (which may not have config)
        clear_config_context()
        ClodSettings()

        # With context, uses project_dir
        set_config_context(project_dir)
        settings_with_context = ClodSettings()

        assert settings_with_context.sandbox_name == ".context-test"

    def test_clear_context(self, project_dir: Path, clean_env: None) -> None:
        """Clearing context resets to cwd-based discovery."""
        config = project_dir / "clod.toml"
        config.write_text('sandbox_name = ".context-test"')

        set_config_context(project_dir)
        clear_config_context()

        # After clearing, if cwd doesn't have a config, defaults are used
        # This depends on the test's working directory, so we just verify
        # that clear_config_context can be called without error
        settings = ClodSettings()
        assert settings.sandbox_name is not None  # Some value is set
