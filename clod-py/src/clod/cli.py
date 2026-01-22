"""CLI for clod using Click.

Provides the 'clod jail' command to run Claude in a bubblewrap sandbox.
"""

import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import click

from clod.config import (
    ClodSettings,
    ConfigError,
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
@click.option(
    "--dry-run",
    is_flag=True,
    help="Print the bwrap command without executing it",
)
@click.option(
    "--shell",
    is_flag=True,
    help="Drop into an interactive shell instead of running claude",
)
@click.argument("claude_args", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def jail(
    ctx: click.Context,
    verbose: bool,
    no_network: bool,
    dry_run: bool,
    shell: bool,
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

        \b
        # Print bwrap command without running
        clod jail --dry-run

        \b
        # Drop into interactive shell inside sandbox
        clod jail --shell
    """
    # Check for bubblewrap
    if not shutil.which("bwrap"):
        click.echo(
            "Error: bubblewrap not found. Install: sudo apt install bubblewrap",
            err=True,
        )
        sys.exit(1)

    # Check for claude (not required for --shell mode)
    if not shell and not shutil.which("claude"):
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

    # Determine the command to run inside sandbox
    if shell:
        inner_cmd = [settings.shell]
    else:
        inner_cmd = ["claude"]
        if claude_args:
            inner_cmd.extend(claude_args)

    # Print info if verbose or dry-run
    if verbose or dry_run:
        click.echo("clod")
        click.echo("   Profile: dev")
        click.echo(f"   Project: {project_dir}")
        click.echo(f"   Sandbox: {sandbox_home}")
        if shell:
            click.echo(f"   Shell:   {settings.shell}")
        else:
            click.echo(f"   Claude:  {shutil.which('claude')}")
        click.echo()

    # Build command
    cmd = builder.build()
    cmd.extend(["--"] + inner_cmd)

    # Handle dry-run: print command and exit
    if dry_run:
        click.echo("# bwrap command:")
        click.echo(shlex.join(cmd))
        return

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
