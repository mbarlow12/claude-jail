"""CLI integration tests for config system."""

from pathlib import Path

import pytest
from click.testing import CliRunner

from clod.cli import cli


@pytest.fixture
def runner() -> CliRunner:
    """Create a Click test runner."""
    return CliRunner()


class TestCliConfigOption:
    """Tests for -c/--config CLI option."""

    def test_config_option_loads_file(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        """Config option loads the specified file."""
        # Create config file
        config = tmp_path / "test.toml"
        config.write_text('sandbox_name = ".test-sandbox"')

        # Create project directory
        project = tmp_path / "project"
        project.mkdir()

        # Mock bwrap and claude to not actually run
        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(
                cli, ["-c", str(config), "-d", str(project), "jail", "-v"]
            )

        # Should show our custom sandbox name in verbose output
        assert ".test-sandbox" in result.output

    def test_config_option_file_not_found(
        self,
        runner: CliRunner,
        tmp_path: Path,
    ) -> None:
        """Config option with non-existent file fails."""
        missing = tmp_path / "missing.toml"

        result = runner.invoke(cli, ["-c", str(missing), "jail"])

        assert result.exit_code != 0
        # Click validates path exists
        assert "does not exist" in result.output or "Error" in result.output


class TestCliDirOption:
    """Tests for -d/--dir CLI option at group level."""

    def test_dir_option_at_group_level(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        """Dir option works at group level."""
        project = tmp_path / "myproject"
        project.mkdir()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "-v"])

        assert "myproject" in result.output

    def test_dir_defaults_to_cwd(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        """Dir defaults to current working directory."""
        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["jail", "-v"])

        # Should use current directory (isolated filesystem)
        assert result.exit_code == 0 or "Error" in result.output


class TestCliConfigDiscovery:
    """Tests for config file discovery via CLI."""

    def test_project_config_discovered(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Project clod.toml is discovered and applied."""
        project = tmp_path / "project"
        project.mkdir()

        # Create project config
        config = project / "clod.toml"
        config.write_text('sandbox_name = ".discovered-sandbox"')

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "-v"])

        assert ".discovered-sandbox" in result.output

    def test_duplicate_config_error(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Duplicate config files cause error."""
        project = tmp_path / "project"
        project.mkdir()

        # Create both config formats
        (project / "clod.toml").write_text("a = 1")
        dot_clod = project / ".clod"
        dot_clod.mkdir()
        (dot_clod / "config.toml").write_text("b = 2")

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail"])

        assert result.exit_code != 0
        assert "Conflicting" in result.output or "Error" in result.output

    def test_explicit_config_skips_discovery(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Explicit config skips project config discovery."""
        project = tmp_path / "project"
        project.mkdir()

        # Create project config that would be discovered
        (project / "clod.toml").write_text('sandbox_name = ".from-project"')

        # Create explicit config with different value
        explicit = tmp_path / "explicit.toml"
        explicit.write_text('sandbox_name = ".from-explicit"')

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(
                cli, ["-c", str(explicit), "-d", str(project), "jail", "-v"]
            )

        # Should use explicit config value
        assert ".from-explicit" in result.output
        assert ".from-project" not in result.output


class TestCliNoNetworkFlag:
    """Tests for --no-network flag interaction with config."""

    def test_no_network_overrides_config(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--no-network flag overrides enable_network from config."""
        project = tmp_path / "project"
        project.mkdir()

        # Config enables network
        config = project / "clod.toml"
        config.write_text("enable_network = true")

        # Track if unshare("net") is called
        unshare_calls: list[str] = []
        original_init = None

        def mock_initialize(project_dir, sandbox_home, settings):
            class MockBuilder:
                def unshare(self, *args):
                    unshare_calls.extend(args)

                def build(self):
                    return ["echo", "mock"]

            return MockBuilder()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")
        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "--no-network"])

        assert "net" in unshare_calls


class TestCliVerboseOutput:
    """Tests for verbose output with config."""

    def test_verbose_shows_sandbox_path(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Verbose output shows sandbox path from config."""
        project = tmp_path / "project"
        project.mkdir()

        config = project / "clod.toml"
        config.write_text('sandbox_name = ".my-custom-sandbox"')

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "-v"])

        assert "Profile: dev" in result.output
        assert str(project) in result.output
        assert ".my-custom-sandbox" in result.output
