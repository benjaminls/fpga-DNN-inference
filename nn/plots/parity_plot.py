"""Parity plot for regression predictions."""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def plot_parity(y_true: np.ndarray, y_pred: np.ndarray, out_path: str | Path) -> None:
    plt.figure(figsize=(5, 5))
    plt.scatter(y_true, y_pred, s=4, alpha=0.5)
    min_v = min(float(y_true.min()), float(y_pred.min()))
    max_v = max(float(y_true.max()), float(y_pred.max()))
    plt.plot([min_v, max_v], [min_v, max_v], "k--", linewidth=1)
    plt.xlabel("actual")
    plt.ylabel("predicted")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()
