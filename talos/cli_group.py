"""
Defines the main CLI group.
"""

from loguru import logger
import click
from talos.logging import setup_logging
from talos.cmd.init import init as init_command


@click.group()
@click.option(
    "--log-format",
    type=str,
    default="text",
    help="Output logs in specific format",
)
def main_cli(log_format: str) -> None:
    """Main command line interface group for the talos-local CLI tool."""
    setup_logging(log_format=log_format)
    logger.info("Starting Talos CLI")


main_cli.add_command(init_command)
