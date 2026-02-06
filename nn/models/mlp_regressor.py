"""Simple MLP regressor for tabular data."""

from __future__ import annotations

from typing import List

import torch
from torch import nn


# TODO: add batchnorm, activations, etc. as options
# TODO: add tensorflow/keras switching or different function
def build_mlp(input_dim: int, hidden: List[int], dropout: float = 0.0) -> nn.Module:
    layers: List[nn.Module] = []
    prev = input_dim
    for h in hidden:
        layers.append(nn.Linear(prev, h))
        layers.append(nn.ReLU())
        if dropout > 0.0:
            layers.append(nn.Dropout(dropout))
        prev = h
    layers.append(nn.Linear(prev, 1))
    return nn.Sequential(*layers)
