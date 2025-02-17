import click
from loguru import logger
from datetime import datetime


@click.command()
def init():
    """Initialize a new Talos project."""
    logger.info("Initializing new Talos project")
    try:
        # Your initialization logic here
        logger.debug("Project initialization started")

        # Example structured logging
        logger.info(
            "Project created",
            project_name="talos",
            timestamp=datetime.now().isoformat(),
        )
    except Exception as e:
        logger.exception(f"Failed to initialize project: {e}")
        raise click.ClickException("Project initialization failed")
