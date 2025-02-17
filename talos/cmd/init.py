import click
from loguru import logger
from datetime import datetime


@click.command()
@click.pass_obj
def init(obj: dict):
    """Initialize a new Talos project."""
    logger.info("Initializing new Talos project")

    setup_completed = False
    cleanup_vms = False
    local_db_holder = obj["local_db_holder"]
    config = obj["config"]

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

        if not setup_completed:
            cleanup_vms = True

        raise click.ClickException("Project initialization failed")
    finally:
        if cleanup_vms:
            logger.info("Cleaning up VMs")
            # TODO: Implement VM cleanup
