"""
Defines the main CLI group.
"""

from loguru import logger
import click
from talos.config import TalosLocalConfig
from talos.db import TalosLocalDBHolder
from talos.logging import setup_logging
from talos.cmd.init import init as init_command


@click.group()
@click.option(
    "--log-format",
    type=str,
    default="text",
    help="Output logs in specific format",
)
@click.option(
    "--log-level",
    type=str,
    default="INFO",
    help="Set the log level",
)
@click.option(
    "--config",
    type=click.Path(exists=True),
    default="tl-config.toml",
    help="Path to the project configuration file",
)
@click.option(
    "--local-db",
    type=click.Path(),
    default="local-db.json",
    help="Path to the local database file",
)
def main_cli(
    log_format: str, log_level: str, config: click.Path, local_db: click.Path
) -> None:
    """Main command line interface group for the talos-local CLI tool."""
    setup_logging(log_format=log_format, log_level=log_level)
    resulting_config = TalosLocalConfig.load_config(config)
    resulting_local_db_holder = TalosLocalDBHolder(local_db)

    ctx = click.get_current_context()
    ctx.ensure_object(dict)
    ctx.obj["config"] = resulting_config
    ctx.obj["local_db_holder"] = resulting_local_db_holder

    logger.info("Starting talos-local CLI")


main_cli.add_command(init_command)
