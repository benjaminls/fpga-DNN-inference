"""I/O helpers for experiment outputs."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict
import numpy as np


def ensure_dir(path: str | Path) -> Path:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def save_json(path: str | Path, data: Dict[str, Any]) -> None:
    p = Path(path)
    with p.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)


def save_numpy(path: str | Path, array: Any) -> None:
    p = Path(path)
    with p.open("wb") as f:
        np.save(f, array)


def save_scalers(path: str | Path, scalers: Dict[str, Any]) -> None:
    p = Path(path)
    with p.open("wb") as f:
        np.save(f, scalers)