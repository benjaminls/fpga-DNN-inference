"""Emit a minimal hls4ml config stub for a trained model."""

from __future__ import annotations

from pathlib import Path

import yaml


def emit_stub(onnx_path: str | Path, out_path: str | Path, precision: str = "ap_fixed<16,6>") -> None:
    cfg = {
        "Backend": "Vivado",
        "ProjectName": "hls4ml_project",
        "Part": "xc7a200tsbg484-1",
        "InputData": str(onnx_path),
        "Precision": precision,
        "Model": {
            "Precision": precision,
            "ReuseFactor": 1,
        },
    }
    out_path = Path(out_path)
    with out_path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)
