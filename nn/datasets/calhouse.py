"""California Housing dataset loader from the local zip bundle."""

from __future__ import annotations

from pathlib import Path
from typing import Tuple

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler


def load_dataset(cfg: dict) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, StandardScaler, StandardScaler]:
    ds = cfg["dataset"]
    zip_path = Path(ds["zip_path"])
    if not zip_path.exists():
        raise FileNotFoundError(f"dataset zip not found: {zip_path}")

    # The zip contains a CSV named 'housing.csv'
    df = pd.read_csv(zip_path, compression="zip")
    # Drop rows with missing values to avoid NaNs in training/metrics
    df = df.dropna()
    features = ds["features"]
    target = ds["target"]

    if target not in df.columns:
        raise ValueError(f"target column not found: {target}")
    for f in features:
        if f not in df.columns:
            raise ValueError(f"feature column not found: {f}")

    X = df[features].to_numpy(dtype=np.float32)
    y = df[target].to_numpy(dtype=np.float32)

    split = ds.get("split", [0.8, 0.1, 0.1])
    train_size, val_size, test_size = split
    if abs(train_size + val_size + test_size - 1.0) > 1e-6:
        raise ValueError("split must sum to 1.0")

    xscaler = StandardScaler()
    yscaler = StandardScaler()
    X = xscaler.fit_transform(X)
    y = yscaler.fit_transform(y.reshape(-1, 1)).flatten()

    X_train, X_tmp, y_train, y_tmp = train_test_split(
        X, y, test_size=(1.0 - train_size), random_state=cfg["training"]["seed"]
    )
    rel_val = val_size / (val_size + test_size)
    X_val, X_test, y_val, y_test = train_test_split(
        X_tmp, y_tmp, test_size=(1.0 - rel_val), random_state=cfg["training"]["seed"]
    )

    # scaler = StandardScaler()
    # X_train = scaler.fit_transform(X_train)
    # X_val = scaler.transform(X_val)
    # X_test = scaler.transform(X_test)

    return X_train, y_train, X_val, y_val, X_test, y_test, xscaler, yscaler
