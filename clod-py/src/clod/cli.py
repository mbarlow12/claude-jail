"""CLI for clod using Click.

Provides the 'clod jail' command to run Claude in a bubblewrap sandbox.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import click

from clod.config import ClodSettings, get_sandbox_home
from clod.sandbox import initialize_sandbox


@click.group()
def cli() -> None:
    """clod - Minimal bubblewrap sandbox for Claude Code."""
    pass


@cli.command()
@click.option(
    "-d",
    "--dir",
    "project_dir",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=None,
    help="Project directory (default: current directory)",
)
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
def jail(
    project_dir: Path | None,
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

    # Resolve project directory
    if project_dir is None:
        project_dir = Path.cwd()
    project_dir = project_dir.resolve()

    # Load settings
    settings = ClodSettings()
    if no_network:
        settings.enable_network = False

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
