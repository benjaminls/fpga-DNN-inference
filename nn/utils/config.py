"""Config loading and minimal validation."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

import yaml


def load_config(path: str | Path) -> Dict[str, Any]:
    cfg_path = Path(path)
    with cfg_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    # Minimal validation
    for key in ["dataset", "model", "training", "metrics", "export", "outputs"]:
        if key not in cfg:
            raise ValueError(f"missing config section: {key}")
    return cfg
