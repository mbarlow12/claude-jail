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
            runner.invoke(cli, ["-d", str(project), "jail", "--no-network"])

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


class TestCliDryRunFlag:
    """Tests for --dry-run flag."""

    def test_dry_run_prints_command(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--dry-run prints the bwrap command without running."""
        project = tmp_path / "project"
        project.mkdir()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        # Mock initialize_sandbox to return a builder with known args
        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            builder = BwrapBuilder()
            builder.bind_args.extend(["--bind", str(project_dir), str(project_dir)])
            return builder

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "--dry-run"])

        assert result.exit_code == 0
        assert "bwrap" in result.output
        assert "claude" in result.output
        assert "# bwrap command:" in result.output

    def test_dry_run_shows_verbose_info(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--dry-run automatically shows verbose info."""
        project = tmp_path / "project"
        project.mkdir()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            return BwrapBuilder()

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "--dry-run"])

        # Should show info even without -v flag
        assert "Profile: dev" in result.output
        assert str(project) in result.output

    def test_dry_run_does_not_execute(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--dry-run does not actually execute subprocess.run."""
        project = tmp_path / "project"
        project.mkdir()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        run_called = []

        def mock_run(*args, **kwargs):
            run_called.append(True)

        monkeypatch.setattr("subprocess.run", mock_run)

        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            return BwrapBuilder()

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            runner.invoke(cli, ["-d", str(project), "jail", "--dry-run"])

        assert len(run_called) == 0


class TestCliShellFlag:
    """Tests for --shell flag."""

    def test_shell_does_not_require_claude(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--shell mode does not require claude to be installed."""
        project = tmp_path / "project"
        project.mkdir()

        def mock_which(cmd):
            if cmd == "bwrap":
                return "/usr/bin/bwrap"
            if cmd == "claude":
                return None  # claude not found
            return f"/usr/bin/{cmd}"

        monkeypatch.setattr("shutil.which", mock_which)

        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            return BwrapBuilder()

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)
        monkeypatch.setattr("subprocess.run", lambda *a, **kw: None)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(cli, ["-d", str(project), "jail", "--shell"])

        # Should not fail with "claude not found"
        assert "claude not found" not in result.output

    def test_shell_uses_shell_from_settings(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--shell mode uses shell from settings."""
        project = tmp_path / "project"
        project.mkdir()

        config = project / "clod.toml"
        config.write_text('shell = "/bin/zsh"')

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            return BwrapBuilder()

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(
                cli, ["-d", str(project), "jail", "--shell", "--dry-run"]
            )

        # Command should contain the shell, not claude
        assert "/bin/zsh" in result.output
        assert "claude" not in result.output.split("# bwrap command:")[-1]

    def test_shell_verbose_shows_shell_path(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """--shell -v shows shell path instead of claude path."""
        project = tmp_path / "project"
        project.mkdir()

        monkeypatch.setattr("shutil.which", lambda x: f"/usr/bin/{x}")

        def mock_initialize(project_dir, sandbox_home, settings):
            from clod.bwrap import BwrapBuilder

            return BwrapBuilder()

        monkeypatch.setattr("clod.cli.initialize_sandbox", mock_initialize)

        with runner.isolated_filesystem(temp_dir=tmp_path):
            result = runner.invoke(
                cli, ["-d", str(project), "jail", "--shell", "--dry-run"]
            )

        assert "Shell:" in result.output
        assert "Claude:" not in result.output
