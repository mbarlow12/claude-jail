"""CLI for clod using Click.

Provides the 'clod jail' command to run Claude in a bubblewrap sandbox.
"""

import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import click

from clod.config import (
    ClodSettings,
    ConfigError,
    get_sandbox_home,
    load_settings,
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

    # Resolve project directory
    if project_dir is None:
        project_dir = Path.cwd()
    project_dir = project_dir.resolve()

    # Load settings from config files
    try:
        settings = load_settings(project_dir, explicit_config=config_file)
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
        settings = ClodSettings(
            **{**settings.model_dump(), "enable_network": False}
        )

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
        click.echo(f"   Profile: dev")
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


if __name__ == "__main__":
    cli()
