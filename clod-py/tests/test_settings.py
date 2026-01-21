"""Tests for config/settings.py ClodSettings."""

from pathlib import Path

import pytest

from clod.config import ClodSettings, SandboxSettings, get_sandbox_home


class TestClodSettings:
    """Tests for ClodSettings."""

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
