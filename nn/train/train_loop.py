"""Training loop for tabular regression."""

from __future__ import annotations

from typing import Dict, Tuple

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, TensorDataset
from tqdm import tqdm


def run_train(
    model: nn.Module,
    train: Tuple[np.ndarray, np.ndarray],
    val: Tuple[np.ndarray, np.ndarray],
    cfg: Dict,
) -> Tuple[nn.Module, list[float], list[float]]:
    X_train, y_train = train
    X_val, y_val = val

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = model.to(device)

    train_ds = TensorDataset(
        torch.from_numpy(X_train).float(), torch.from_numpy(y_train).float().unsqueeze(1)
    )
    val_ds = TensorDataset(
        torch.from_numpy(X_val).float(), torch.from_numpy(y_val).float().unsqueeze(1)
    )

    batch_size = cfg["training"]["batch_size"]
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

    optim = torch.optim.Adam(
        model.parameters(), lr=cfg["training"]["lr"], weight_decay=cfg["training"]["weight_decay"]
    )
    loss_fn = nn.MSELoss()

    train_losses: list[float] = []
    val_losses: list[float] = []

    epochs = cfg["training"]["epochs"]
    for epoch in range(epochs):
        model.train()
        total = 0.0
        for xb, yb in tqdm(train_loader, desc=f"epoch {epoch+1}/{epochs} train"):
            xb = xb.to(device)
            yb = yb.to(device)
            optim.zero_grad()
            preds = model(xb)
            loss = loss_fn(preds, yb)
            loss.backward()
            optim.step()
            total += float(loss.item()) * xb.size(0)
        train_loss = total / len(train_ds)
        train_losses.append(train_loss)

        model.eval()
        total = 0.0
        with torch.no_grad():
            for xb, yb in tqdm(val_loader, desc=f"epoch {epoch+1}/{epochs} val"):
                xb = xb.to(device)
                yb = yb.to(device)
                preds = model(xb)
                loss = loss_fn(preds, yb)
                total += float(loss.item()) * xb.size(0)
        val_loss = total / len(val_ds)
        val_losses.append(val_loss)

        print(f"epoch {epoch+1}/{epochs} train_loss={train_loss:.6f} val_loss={val_loss:.6f}")

    return model, train_losses, val_losses
