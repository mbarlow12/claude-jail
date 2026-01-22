"""Pytest fixtures for clod tests."""

from pathlib import Path

import pytest


@pytest.fixture
def temp_dir(tmp_path: Path) -> Path:
    """Provide a temporary directory for tests."""
    return tmp_path


@pytest.fixture
def project_dir(tmp_path: Path) -> Path:
    """Provide a temporary project directory."""
    project = tmp_path / "project"
    project.mkdir()
    return project


@pytest.fixture
def mock_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Provide a mock home directory and set HOME env var."""
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    return home


@pytest.fixture
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Remove clod-related environment variables."""
    env_vars = [
        "CLOD_CONFIG_HOME",
        "XDG_CONFIG_HOME",
        "CLOD_SANDBOX_NAME",
        "CLOD_ENABLE_NETWORK",
        "CLOD_TERM",
        "CLOD_LANG",
        "CLOD_SHELL",
    ]
    for var in env_vars:
        monkeypatch.delenv(var, raising=False)


@pytest.fixture
def config_home(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, clean_env: None
) -> Path:
    """Provide a mock CLOD_CONFIG_HOME directory.

    Depends on clean_env to ensure env is clean before setting CLOD_CONFIG_HOME.
    """
    config = tmp_path / "clod-config"
    config.mkdir()
    monkeypatch.setenv("CLOD_CONFIG_HOME", str(config))
    return config


@pytest.fixture
def xdg_config_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Provide a mock XDG_CONFIG_HOME directory."""
    xdg = tmp_path / "xdg-config"
    xdg.mkdir()
    monkeypatch.setenv("XDG_CONFIG_HOME", str(xdg))
    return xdg
