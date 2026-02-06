"""Evaluation helpers for regression models."""

from __future__ import annotations

from typing import Dict, Tuple

import numpy as np
import torch

from nn.metrics import regression


def run_eval(model, test: Tuple[np.ndarray, np.ndarray]) -> Dict[str, float]:
    X_test, y_test = test
    device = next(model.parameters()).device
    model.eval()
    with torch.no_grad():
        preds = model(torch.from_numpy(X_test).float().to(device)).cpu().numpy().squeeze()
    return {
        "mae": regression.mae(y_test, preds),
        "rmse": regression.rmse(y_test, preds),
        "r2": regression.r2(y_test, preds),
    }
