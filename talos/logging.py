from loguru import logger
import sys


def setup_logging(log_format: str = "text") -> None:
    """Configure logging with either JSON or plaintext format."""
    # Remove default logger
    logger.remove()

    if log_format == "json":
        logger.add(sys.stderr, serialize=True)
    else:
        logger.add(
            sys.stderr,
            format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
            level="INFO"
        )
