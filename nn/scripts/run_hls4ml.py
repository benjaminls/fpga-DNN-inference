#!/usr/bin/env python3
"""Generate hls4ml project from ONNX using a YAML config."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict
import sys
import os
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Ensure Vitis binaries are on PATH if XILINX_VITIS is set (possibly unnecessary)
if "XILINX_VITIS" in os.environ:
    os.environ["PATH"] = os.environ["XILINX_VITIS"] + "/bin:" + os.environ["PATH"]


def _load_config(path: str | Path) -> Dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _build_hls_config(cfg: Dict[str, Any]) -> Dict[str, Any]:
    h = cfg["hls4ml"]
    hls_config: Dict[str, Any] = {
        "Model": {
            "Precision": h.get("precision", "ap_fixed<16,6>"),
            "ReuseFactor": int(h.get("reuse_factor", 1)),
            "Strategy": h.get("strategy", "Resource"),
        }
    }

    # Optional per-layer overrides
    layer_precision = h.get("layer_precision", {}) or {}
    layer_reuse = h.get("layer_reuse", {}) or {}
    if layer_precision or layer_reuse:
        hls_config["LayerName"] = {}
        for name, prec in layer_precision.items():
            hls_config["LayerName"].setdefault(name, {})["Precision"] = prec
        for name, reuse in layer_reuse.items():
            hls_config["LayerName"].setdefault(name, {})["ReuseFactor"] = int(reuse)

    return hls_config


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="YAML hls4ml config file")
    ap.add_argument("--build", action="store_true", help="Run HLS build")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    cfg = _load_config(args.config)
    model_cfg = cfg["model"]
    source = model_cfg.get("source", "onnx")
    onnx_path = Path(model_cfg.get("onnx_path", "")).resolve()
    out_dir = Path(model_cfg["output_dir"]).resolve()

    try:
        import hls4ml  # type: ignore
    except Exception as exc:  # pragma: no cover - environment-dependent
        raise RuntimeError("hls4ml is not installed in this environment") from exc

    hls_config = _build_hls_config(cfg)

    hls_kwargs = {
        "backend": cfg["hls4ml"].get("backend", "Vitis"),       # Vivado 2025.2 lacks vivado_hls support
        "part": cfg["hls4ml"].get("part", "xc7a200tsbg484-1"),  # default Artix-7 T200
        "clock_period": float(cfg["hls4ml"].get("clock_period", 10.0)), # ns
        "io_type": cfg["hls4ml"].get("io_type", "io_stream"),
    }
    if "flow_target" in cfg["hls4ml"]:
        hls_kwargs["flow_target"] = cfg["hls4ml"]["flow_target"]

    if args.verbose:
        print(f"hls4ml config ({args.config}):")
        print(yaml.dump(hls_config, sort_keys=False))
        print("hls4ml kwargs:")
        print(yaml.dump(hls_kwargs, sort_keys=False))   

    if source == "onnx":
        hls_model = hls4ml.converters.convert_from_onnx_model(
            str(onnx_path), hls_config=hls_config, output_dir=str(out_dir), **hls_kwargs
        )
    elif source == "pytorch":
        from nn.models import mlp_regressor
        import torch
        import json

        pt_cfg = model_cfg["pytorch"]
        input_dim = int(pt_cfg.get("input_dim", 0))
        hidden = pt_cfg.get("hidden", [])
        dropout = float(pt_cfg.get("dropout", 0.0))
        checkpoint = Path(pt_cfg["checkpoint"]).resolve()
        info_path = pt_cfg.get("model_info", "")

        if info_path:
            info = json.loads(Path(info_path).read_text())
            input_dim = int(info.get("input_dim", input_dim))
            hidden = info.get("hidden", hidden)

        if input_dim <= 0 or not hidden:
            raise ValueError("pytorch.input_dim and pytorch.hidden must be set (or provide model_info)")

        model = mlp_regressor.build_mlp(input_dim=input_dim, hidden=hidden, dropout=dropout)
        model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
        model.eval()

        # hls4ml expects InputShape for PyTorch models
        hls_config["InputShape"] = [(input_dim,)]

        hls_model = hls4ml.converters.convert_from_pytorch_model(
            model,
            hls_config=hls_config,
            output_dir=str(out_dir),
            **hls_kwargs,
        )
    else:
        raise ValueError(f"unknown model.source: {source}")

    # Always emit project files
    hls_model.write()

    if args.build:
        backend = cfg["hls4ml"].get("backend", "Vitis")
        build_tcl = out_dir / "build_prj.tcl"
        if backend.lower() == "vitis" and cfg["hls4ml"].get("vitis_patch_array_partition", True):
            if build_tcl.exists():
                lines = build_tcl.read_text().splitlines()
                lines = [ln for ln in lines if "config_array_partition -maximum_size" not in ln]
                build_tcl.write_text("\n".join(lines) + "\n")

        if backend.lower() == "vitis":
            runner = cfg["hls4ml"].get("vitis_runner", "vitis-run")  # nominally vitis-run, but vitis_hls in older versions
            if runner == "vitis-run":
                cmd = [runner, "--mode", "hls", "--tcl", str(build_tcl)]
            else:
                cmd = [runner, "-f", str(build_tcl)]
            subprocess.run(cmd, cwd=str(out_dir), check=True)
        else:
            hls_model.build(csim=True, synth=True)

    print(f"hls4ml project generated at: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
