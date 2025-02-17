from __future__ import annotations
import os
from pathlib import Path
from json import load as json_load, dump as json_dump
from sys import getdefaultencoding

from loguru import logger
from pydantic import BaseModel


class TalosLocalDB(BaseModel):
    """Local database for the talos-local CLI."""

    @classmethod
    def load_config(cls, config_path: Path) -> TalosLocalDB:
        """Load the configuration from the given path."""
        if not os.path.exists(config_path):
            logger.warning(f"Config file not found: {config_path}")
            return cls()

        with open(config_path, "rb") as f:
            config = json_load(f)

        return cls.model_validate(config)


class TalosLocalDBHolder:
    """Holder for the local database."""

    local_db: TalosLocalDB
    db_path: Path

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.local_db = TalosLocalDB.load_config(db_path)

    def save(self):
        """Save the local database."""
        # Create parent directories if they don't exist
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.db_path, "w", encoding=getdefaultencoding()) as f:
            json_dump(self.local_db.model_dump(), f)
