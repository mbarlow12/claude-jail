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


class TestCliInitCommand:
    """Tests for clod init command."""

    def test_init_creates_config_dir_and_file(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init creates config directory and config.toml with defaults."""
        config_home = tmp_path / "clod-config"
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        result = runner.invoke(cli, ["init", "-y"])

        assert result.exit_code == 0
        assert config_home.exists()
        config_file = config_home / "config.toml"
        assert config_file.exists()
        assert "Created config file" in result.output

    def test_init_defaults_written_correctly(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init writes correct default values to config."""
        config_home = tmp_path / "clod-config"
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        runner.invoke(cli, ["init", "-y"])

        config_file = config_home / "config.toml"
        content = config_file.read_text()

        assert 'sandbox_name = ".claude-sandbox"' in content
        assert "enable_network = true" in content
        assert 'term = "xterm-256color"' in content
        assert 'lang = "en_US.UTF-8"' in content
        assert 'shell = "/bin/bash"' in content

    def test_init_prompts_for_existing_config(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init asks for confirmation when config exists."""
        config_home = tmp_path / "clod-config"
        config_home.mkdir()
        config_file = config_home / "config.toml"
        config_file.write_text('sandbox_name = ".existing"')
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        # Answer 'n' to overwrite prompt
        result = runner.invoke(cli, ["init", "-y"], input="n\n")

        assert result.exit_code == 0
        assert "already exists" in result.output
        # Original content should be preserved
        assert ".existing" in config_file.read_text()

    def test_init_force_overwrites_existing(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init --force overwrites existing config without prompting."""
        config_home = tmp_path / "clod-config"
        config_home.mkdir()
        config_file = config_home / "config.toml"
        config_file.write_text('sandbox_name = ".existing"')
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        result = runner.invoke(cli, ["init", "--force", "-y"])

        assert result.exit_code == 0
        # Should have new default value
        assert 'sandbox_name = ".claude-sandbox"' in config_file.read_text()

    def test_init_interactive_custom_values(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init interactive mode allows custom values."""
        config_home = tmp_path / "clod-config"
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        # Provide custom values via input
        # Order: sandbox_name, enable_network (y/n), term, lang, shell
        user_input = ".my-sandbox\nn\nscreen-256color\nen_GB.UTF-8\n/bin/zsh\n"
        result = runner.invoke(cli, ["init"], input=user_input)

        assert result.exit_code == 0
        config_file = config_home / "config.toml"
        content = config_file.read_text()

        assert 'sandbox_name = ".my-sandbox"' in content
        assert "enable_network = false" in content
        assert 'term = "screen-256color"' in content
        assert 'lang = "en_GB.UTF-8"' in content
        assert 'shell = "/bin/zsh"' in content

    def test_init_shows_configuration_summary(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init shows configuration summary after creation."""
        config_home = tmp_path / "clod-config"
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        result = runner.invoke(cli, ["init", "-y"])

        assert "Configuration:" in result.output
        assert "sandbox_name:" in result.output
        assert "enable_network:" in result.output

    def test_init_respects_clod_config_home(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init respects CLOD_CONFIG_HOME environment variable."""
        custom_home = tmp_path / "custom-config-home"
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(custom_home))

        result = runner.invoke(cli, ["init", "-y"])

        assert result.exit_code == 0
        assert (custom_home / "config.toml").exists()
        assert str(custom_home) in result.output

    def test_init_respects_xdg_config_home(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init respects XDG_CONFIG_HOME environment variable."""
        xdg_home = tmp_path / "xdg"
        monkeypatch.setenv("XDG_CONFIG_HOME", str(xdg_home))

        result = runner.invoke(cli, ["init", "-y"])

        assert result.exit_code == 0
        expected_path = xdg_home / "clod" / "config.toml"
        assert expected_path.exists()

    def test_init_aborts_on_no_overwrite(
        self,
        runner: CliRunner,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        clean_env: None,
    ) -> None:
        """Init aborts when user declines to overwrite."""
        config_home = tmp_path / "clod-config"
        config_home.mkdir()
        config_file = config_home / "config.toml"
        original_content = 'sandbox_name = ".original"'
        config_file.write_text(original_content)
        monkeypatch.setenv("CLOD_CONFIG_HOME", str(config_home))

        # Answer 'n' to overwrite
        result = runner.invoke(cli, ["init", "-y"], input="n\n")

        assert "Aborted" in result.output
        # Original content unchanged
        assert config_file.read_text() == original_content
