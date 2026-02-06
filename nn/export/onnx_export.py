"""Export PyTorch model to ONNX."""

from __future__ import annotations

from pathlib import Path

import torch


def export_onnx(model, input_dim: int, out_path: str | Path) -> None:
    model.eval()
    dummy = torch.zeros(1, input_dim, dtype=torch.float32)
    out_path = Path(out_path)
    torch.onnx.export(
        model,
        dummy,
        out_path,
        input_names=["input"],
        output_names=["output"],
        opset_version=13,
    )
