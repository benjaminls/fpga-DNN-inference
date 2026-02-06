#!/usr/bin/env python3
"""Generate hls4ml project from ONNX using a YAML config."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, Union
import sys
import os
import subprocess
import json
import yaml
import warnings

import tensorflow as tf
import torch
import onnx
try:
    import hls4ml  # type: ignore
except Exception as exc:  # pragma: no cover - environment-dependent
    raise RuntimeError("hls4ml is not installed in this environment") from exc

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# now we can import from nn
from nn.models import mlp_regressor

HLSCONFIG = Dict[str, Any]
MODEL = Union[torch.nn.Module, tf.keras.Model, onnx.ModelProto]

# Ensure Vitis binaries are on PATH if XILINX_VITIS is set (possibly unnecessary)
if "XILINX_VITIS" in os.environ:
    os.environ["PATH"] = os.environ["XILINX_VITIS"] + "/bin:" + os.environ["PATH"]


def _load_config(path: str | Path) -> Dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)

def _get_input_dim(cfg: Dict[str, Any]) -> int:
    """Determine input dimension from config, either from model_info or pytorch section."""
    m = cfg["model"]
    if "model_info" in m:
        info_path = Path(m["model_info"]).resolve()
        if not info_path.exists():
            raise FileNotFoundError(f"model_info set in config but info json file not found: {info_path}")
        info = json.loads(info_path.read_text())
        input_dim = int(info.get("input_dim", 0))
        if input_dim <= 0:
            raise ValueError("input_dim must be > 0 in model_info")
        return input_dim
    elif "pytorch" in m:
        pt_cfg = m["pytorch"]
        input_dim = int(pt_cfg.get("input_dim", 0))
        if input_dim <= 0:
            raise ValueError("pytorch.input_dim must be set and > 0 if using PyTorch model source")
        return input_dim
    else:
        raise ValueError("Cannot determine input dimension: no model_info or pytorch section in config")

def _build_model(cfg: Dict[str, Any]) -> MODEL:
    """Return {TF,pytorch,onnx} model object immediately usable for inference or hls4ml conversion."""
    m = cfg["model"]
    source = m.get("source", "pytorch")
    if source == "onnx":
        onnx_path = Path(m["onnx_path"]).resolve()
        if not onnx_path.exists():
            raise FileNotFoundError(f"ONNX model file not found: {onnx_path}")
        return onnx.load(str(onnx_path))
    elif source == "pytorch":
        pt_cfg = m["pytorch"]
        # input_dim = int(pt_cfg.get("input_dim", 0)) # we get this from dedicated function now
        hidden = pt_cfg.get("hidden", [])
        dropout = float(pt_cfg.get("dropout", 0.0))
        checkpoint = Path(pt_cfg["checkpoint"]).resolve()
        info_path = pt_cfg.get("model_info", "")

        # If model_info set in config, then use it instead
        if info_path:
            info_path = Path(info_path).resolve()
            if not info_path.exists():
                raise FileNotFoundError(f"model_info set in config but info json file not found: {info_path}")
            info = json.loads(info_path.read_text())
            # input_dim = int(info.get("input_dim", input_dim)) # override
            hidden = info.get("hidden", hidden) # override

        input_dim = _get_input_dim(cfg)

        if input_dim <= 0 or not hidden:
            raise ValueError("pytorch.input_dim and pytorch.hidden must be set (or provide model_info)")
        if not checkpoint.exists():
            raise FileNotFoundError(f"PyTorch checkpoint not found ({checkpoint}). Needed to load model weights for hls4ml conversion, even if not training.")

        model = mlp_regressor.build_mlp(input_dim=input_dim, hidden=hidden, dropout=dropout)
        model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
        model.eval()
        return model
    elif source == "tensorflow":
        raise NotImplementedError("TensorFlow model loading not implemented yet")
    else:
        raise ValueError(f"unknown model.source: {source}")


def _build_hls_config(model: Any, cfg: Dict[str, Any]) -> Dict[str, Any]:
    m = cfg["model"]
    h = cfg["hls4ml"]

    model_source = m.get("source", "pytorch")
    if model_source not in ["onnx", "pytorch", "tensorflow"]:
        warnings.warn(f"Unknown model source '{model_source}', expected one of ['onnx', 'pytorch', 'tensorflow']")
    
    if model_source == "tensorflow":
        hls_config: HLSCONFIG = hls4ml.utils.config_from_keras_model(
            model, 
            granularity="model", 
            backend=h.get("backend", "Vitis"),
            default_reuse_factor=int(h.get("reuse_factor", 1)),
            default_precision=h.get("precision", "ap_fixed<16,6>"),
        )
    elif model_source == "pytorch":
        hls_config: HLSCONFIG = hls4ml.utils.config_from_pytorch_model(
            model, 
            input_shape=(_get_input_dim(cfg),),  # hls4ml needs input shape to convert PyTorch models
            granularity="model", 
            backend=h.get("backend", "Vitis"),
            default_reuse_factor=int(h.get("reuse_factor", 1)),
            default_precision=h.get("precision", "ap_fixed<16,6>"),
        )
    elif model_source == "onnx":
        hls_config: HLSCONFIG = hls4ml.utils.config_from_onnx_model(
            model, 
            granularity="model", 
            backend=h.get("backend", "Vitis"),
            default_reuse_factor=int(h.get("reuse_factor", 1)),
            default_precision=h.get("precision", "ap_fixed<16,6>"),
        )
    else:
        hls_config: Dict[str, Any] = {
            "Model": {
                "Precision": h.get("precision", "ap_fixed<16,6>"),
                "ReuseFactor": int(h.get("reuse_factor", 1)),
                "Strategy": h.get("strategy", "Resource"),
                "TraceOutput": bool(h.get("trace_output", False)),
                "BramFactor": int(h.get("bram_factor", 1000000000)),
                "BitExact": h.get("bit_exact", None)
            }
        }
        if hls_config["Model"]["BitExact"] == "None" and hls_config["Model"]["BitExact"] != None:
            warnings.warn(f"BitExact is set to the string 'None'. Recasting as NoneType.")
            hls_config["Model"]["BitExact"] = None

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


def _build_steps(cfg: Dict[str, Any]) -> Dict[str, bool]:
    build_cfg = cfg.get("build", {}) or {}
    return {
        "csim": bool(build_cfg.get("csim", True)),
        "synth": bool(build_cfg.get("synth", True)),
        "cosim": bool(build_cfg.get("cosim", False)),
        "export": bool(build_cfg.get("export", False)),
        "bitfile": bool(build_cfg.get("bitfile", False)),
    }


def _plot_model(hls_model: Any, cfg: Dict[str, Any]) -> None:
    out_path = cfg.get("plot_model", "nn/outputs/hls4ml_model_structure.png")
    # hls_model.plot_model(
    hls4ml.utils.plot_model(
        hls_model,
        show_shapes=True,
        show_precision=True,
        to_file=str(Path(out_path).resolve()),
    )



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="YAML hls4ml config file")
    ap.add_argument("--build", action="store_true", help="Run HLS build")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    cfg = _load_config(args.config)
    model_cfg = cfg["model"]
    source = model_cfg.get("source", "pytorch")
    onnx_path = Path(model_cfg.get("onnx_path", "")).resolve()
    out_dir = Path(model_cfg["output_dir"]).resolve()


    hls_kwargs = {
        "backend": cfg["hls4ml"].get("backend", "Vitis"),       # Vivado 2025.2 lacks vivado_hls support
        "part": cfg["hls4ml"].get("part", "xc7a200tsbg484-1"),  # default Artix-7 T200
        "clock_period": float(cfg["hls4ml"].get("clock_period", 10.0)), # ns
        "io_type": cfg["hls4ml"].get("io_type", "io_stream"),
    }
    if "flow_target" in cfg["hls4ml"]:
        hls_kwargs["flow_target"] = cfg["hls4ml"]["flow_target"]

    if args.verbose:
        print("hls4ml kwargs:")
        print(yaml.dump(hls_kwargs, sort_keys=False))   
    
    # === Build TF/PyTorch/ONNX model ===
    model: MODEL = _build_model(cfg)

    # === Build HLS config ===
    hls_config: HLSCONFIG = _build_hls_config(model, cfg)
    if args.verbose:
        print(f"hls4ml config ({args.config}):")
        print(yaml.dump(hls_config, sort_keys=False))

    # === Model conversion ===
    if source == "onnx":
        hls_model = hls4ml.converters.convert_from_onnx_model(
            str(onnx_path),             # load ONNX model from file path instead of in-memory object
            hls_config=hls_config, 
            output_dir=str(out_dir), 
            **hls_kwargs
        )
    elif source == "pytorch":
        # hls4ml expects InputShape for PyTorch models
        input_dim = _get_input_dim(cfg)
        hls_config["InputShape"] = [(input_dim,)]

        hls_model = hls4ml.converters.convert_from_pytorch_model(
            model,
            hls_config=hls_config,
            output_dir=str(out_dir),
            **hls_kwargs,
        )
    elif source == "tensorflow":
        raise NotImplementedError("TensorFlow model conversion not implemented yet")
    else:
        raise ValueError(f"unknown model.source: {source}")

    # Always emit project files
    hls_model.write()

    _plot_model(hls_model, cfg["hls4ml"])

    if args.build:
        backend = cfg["hls4ml"].get("backend", "Vitis")
        build_steps = _build_steps(cfg)
        build_cfg = cfg.get("build", {}) or {}
        driver = build_cfg.get("driver", "hls4ml")
        build_tcl = out_dir / "build_prj.tcl"
        extra_build_args = build_cfg.get("extra", {}) or {}

        if backend.lower() == "vitis" and cfg["hls4ml"].get("vitis_patch_array_partition", True):
            if build_tcl.exists():
                lines = build_tcl.read_text().splitlines()
                lines = [ln for ln in lines if "config_array_partition -maximum_size" not in ln]
                build_tcl.write_text("\n".join(lines) + "\n")

        if driver == "hls4ml":
            build_kwargs = {
                "csim": build_steps["csim"],
                "synth": build_steps["synth"],
                "cosim": build_steps["cosim"],
                "export": build_steps["export"],
            }
            # Vitis backend does not accept bitfile kwarg
            if backend.lower() != "vitis":
                build_kwargs["bitfile"] = build_steps["bitfile"]
            build_kwargs.update(extra_build_args)
            hls_model.build(**build_kwargs)
        else:
            if backend.lower() == "vitis":
                runner = cfg["hls4ml"].get("vitis_runner", "vitis-run")  # nominally vitis-run, but vitis_hls in older versions
                if runner == "vitis-run":
                    cmd = [runner, "--mode", "hls", "--tcl", str(build_tcl)]
                else:
                    cmd = [runner, "-f", str(build_tcl)]
                subprocess.run(cmd, cwd=str(out_dir), check=True)
            else:
                build_kwargs = {
                    "csim": build_steps["csim"],
                    "synth": build_steps["synth"],
                    "cosim": build_steps["cosim"],
                    "export": build_steps["export"],
                }
                if backend.lower() != "vitis":
                    build_kwargs["bitfile"] = build_steps["bitfile"]
                hls_model.build(**build_kwargs)

        report_cfg = cfg.get("report", {}) or {}
        if report_cfg.get("enable", False):
            try:
                report = hls4ml.report.read_vivado_report(str(out_dir))
            except Exception as exc:
                print(f"warning: could not read HLS report: {exc}")
            else:
                out_json = report_cfg.get("out_json", "")
                if out_json:
                    Path(out_json).write_text(json.dumps(report, indent=2))

    print(f"hls4ml project generated at: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
