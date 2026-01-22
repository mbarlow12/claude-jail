"""CLI for clod using Click.

Provides the 'clod jail' command to run Claude in a bubblewrap sandbox.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import click

from clod.config import (
    ClodSettings,
    ConfigError,
    discover_user_config,
    get_config_home,
    get_sandbox_home,
    set_config_context,
)
from clod.sandbox import initialize_sandbox


@click.group()
@click.option(
    "-c",
    "--config",
    "config_file",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    default=None,
    help="Use specific config file (skips discovery)",
)
@click.option(
    "-d",
    "--dir",
    "project_dir",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=None,
    help="Project directory (default: current directory)",
)
@click.pass_context
def cli(ctx: click.Context, config_file: Path | None, project_dir: Path | None) -> None:
    """clod - Minimal bubblewrap sandbox for Claude Code."""
    # Ensure ctx.obj exists
    ctx.ensure_object(dict)

    # Skip settings loading for init command (doesn't need existing config)
    if ctx.invoked_subcommand == "init":
        return

    # Resolve project directory
    if project_dir is None:
        project_dir = Path.cwd()
    project_dir = project_dir.resolve()

    # Set context for pydantic-settings source discovery
    set_config_context(project_dir, explicit_config=config_file)

    # Load settings (now uses settings_customise_sources)
    try:
        settings = ClodSettings()
    except ConfigError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)

    # Store in context for subcommands
    ctx.obj["settings"] = settings
    ctx.obj["project_dir"] = project_dir
    ctx.obj["config_file"] = config_file


@cli.command()
@click.option(
    "-v",
    "--verbose",
    is_flag=True,
    help="Show sandbox info on start",
)
@click.option(
    "--no-network",
    is_flag=True,
    help="Disable network access",
)
@click.argument("claude_args", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def jail(
    ctx: click.Context,
    verbose: bool,
    no_network: bool,
    claude_args: tuple[str, ...],
) -> None:
    """Run Claude Code in a bubblewrap sandbox.

    This command creates an isolated sandbox environment and runs the claude
    command inside it. The sandbox uses the dev profile configuration,
    providing access to development tools while protecting your home directory.

    Examples:

        \b
        # Run in current directory
        clod jail

        \b
        # Run in specific directory
        clod jail -d ~/myproject

        \b
        # Use specific config file
        clod jail -c myconfig.toml

        \b
        # Pass arguments to claude
        clod jail -- --help
    """
    # Check for bubblewrap
    if not shutil.which("bwrap"):
        click.echo(
            "Error: bubblewrap not found. Install: sudo apt install bubblewrap",
            err=True,
        )
        sys.exit(1)

    # Check for claude
    if not shutil.which("claude"):
        click.echo("Error: claude not found in PATH", err=True)
        sys.exit(1)

    # Get settings and project_dir from context
    settings: ClodSettings = ctx.obj["settings"]
    project_dir: Path = ctx.obj["project_dir"]

    # Override network setting if --no-network flag is used
    if no_network:
        # Create a new settings object with network disabled
        settings = ClodSettings(**{**settings.model_dump(), "enable_network": False})

    # Get sandbox home
    sandbox_home = get_sandbox_home(project_dir, settings)

    # Initialize sandbox and get builder
    builder = initialize_sandbox(project_dir, sandbox_home, settings)

    # Handle network setting
    if not settings.enable_network:
        builder.unshare("net")

    # Print info if verbose
    if verbose:
        click.echo("clod")
        click.echo("   Profile: dev")
        click.echo(f"   Project: {project_dir}")
        click.echo(f"   Sandbox: {sandbox_home}")
        click.echo(f"   Claude:  {shutil.which('claude')}")
        click.echo()

    # Build command
    cmd = builder.build()
    cmd.extend(["--", "claude"])
    if claude_args:
        cmd.extend(claude_args)

    # Run the command
    try:
        subprocess.run(cmd, check=False)
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:
        click.echo(f"Error running sandbox: {e}", err=True)
        sys.exit(1)


@cli.command()
@click.option(
    "-y",
    "--yes",
    is_flag=True,
    help="Accept all defaults without prompting",
)
@click.option(
    "--force",
    is_flag=True,
    help="Overwrite existing config file",
)
@click.pass_context
def init(ctx: click.Context, yes: bool, force: bool) -> None:
    """Initialize user configuration.

    Creates the user config directory and populates it with a default
    config.toml file. By default, interactively prompts for each setting.

    Examples:

        \b
        # Interactive setup
        clod init

        \b
        # Accept all defaults
        clod init -y

        \b
        # Overwrite existing config
        clod init --force
    """
    config_home = get_config_home()
    config_file = config_home / "config.toml"

    # Check if config already exists
    existing_config = discover_user_config()
    if existing_config and not force:
        click.echo(f"Config file already exists: {existing_config}")
        if not click.confirm("Overwrite?", default=False):
            click.echo("Aborted.")
            sys.exit(0)

    # Create config directory
    config_home.mkdir(parents=True, exist_ok=True)

    # Get default values from ClodSettings field defaults
    defaults = {
        "sandbox_name": ClodSettings.model_fields["sandbox_name"].default,
        "enable_network": ClodSettings.model_fields["enable_network"].default,
        "term": ClodSettings.model_fields["term"].default,
        "lang": ClodSettings.model_fields["lang"].default,
        "shell": ClodSettings.model_fields["shell"].default,
    }

    if yes:
        # Use all defaults
        values = defaults
        click.echo("Using default configuration...")
    else:
        # Interactive prompts
        click.echo("Configure clod settings (press Enter to accept defaults):\n")

        values = {}

        # sandbox_name
        values["sandbox_name"] = click.prompt(
            "Sandbox directory name",
            default=defaults["sandbox_name"],
            type=str,
        )

        # enable_network
        values["enable_network"] = click.confirm(
            "Enable network access",
            default=defaults["enable_network"],
        )

        # term
        values["term"] = click.prompt(
            "TERM environment variable",
            default=defaults["term"],
            type=str,
        )

        # lang
        values["lang"] = click.prompt(
            "LANG environment variable",
            default=defaults["lang"],
            type=str,
        )

        # shell
        values["shell"] = click.prompt(
            "SHELL environment variable",
            default=defaults["shell"],
            type=str,
        )

        click.echo()

    # Generate TOML content
    toml_lines = [
        "# clod user configuration",
        "# See: https://github.com/mbarlow12/claude-jail/tree/main/clod-py",
        "",
        f'sandbox_name = "{values["sandbox_name"]}"',
        f'enable_network = {str(values["enable_network"]).lower()}',
        f'term = "{values["term"]}"',
        f'lang = "{values["lang"]}"',
        f'shell = "{values["shell"]}"',
        "",
    ]
    toml_content = "\n".join(toml_lines)

    # Write config file
    config_file.write_text(toml_content)

    click.echo(f"Created config file: {config_file}")
    click.echo("\nConfiguration:")
    for key, value in values.items():
        click.echo(f"  {key}: {value}")


if __name__ == "__main__":
    cli()
