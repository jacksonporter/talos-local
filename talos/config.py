from __future__ import annotations
import os
from pathlib import Path
from tomllib import load as tomllib_load

from pydantic import BaseModel, Field
from loguru import logger


class TalosVMConfig(BaseModel):
    """Configuration for the VM."""

    name_prefix: str = "talos-linux"
    cpu_count: int = 4
    memory_bytes: int = 4096 * 1024 * 1024
    disk_size_bytes: int = 100 * 1024 * 1024 * 1024
    network_type: str = "shared"


class TalosControlPlaneConfig(BaseModel):
    """Configuration for the control plane."""

    replicas: int = 1
    vm_config: TalosVMConfig = Field(default_factory=TalosVMConfig)
    vm_engine: str | None = "parallels"


class TalosWorkerConfig(BaseModel):
    """Configuration for the worker."""

    replicas: int = 1
    vm_config: TalosVMConfig = Field(default_factory=TalosVMConfig)
    vm_engine: str | None = "parallels"


class TalosLocalConfig(BaseModel):
    """Configuration for the talos-local CLI."""

    name: str
    control_plane: TalosControlPlaneConfig

    @classmethod
    def load_config(cls, config_path: Path) -> TalosLocalConfig:
        """Load the configuration from the given path."""
        if not os.path.exists(config_path):
            logger.error(f"Config file not found: {config_path}")
            raise FileNotFoundError(f"Config file not found: {config_path}")

        with open(config_path, "rb") as f:
            config = tomllib_load(f)

        return cls.model_validate(config)
