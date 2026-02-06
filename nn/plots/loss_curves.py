"""Loss curve plotting."""

from __future__ import annotations

from pathlib import Path
from typing import List

import matplotlib.pyplot as plt


def plot_loss(train_losses: List[float], val_losses: List[float], out_path: str | Path) -> None:
    plt.figure(figsize=(6, 4))
    plt.plot(train_losses, label="train")
    plt.plot(val_losses, label="val")
    plt.xlabel("epoch")
    plt.ylabel("loss")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()
