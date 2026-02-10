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
import shutil

try:
    import tensorflow as tf
except Exception:  # pragma: no cover - optional dependency
    tf = None
import torch
try:
    import onnx
except Exception:  # pragma: no cover - optional dependency
    onnx = None
try:
    import hls4ml  # type: ignore
except Exception as exc:  # pragma: no cover - environment-dependent
    raise RuntimeError("hls4ml is not installed in this environment") from exc # actually need this

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# now we can import from nn
from nn.models import mlp_regressor
from nn.utils import compile as compile_mod

HLSCONFIG = Dict[str, Any]
_TFModel = Any if tf is None else tf.keras.Model
_ONNXModel = Any if onnx is None else onnx.ModelProto
MODEL = Union[torch.nn.Module, _TFModel, _ONNXModel]

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
        if onnx is None:
            raise RuntimeError("onnx is not installed; cannot load ONNX model")
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
        if tf is None:
            raise RuntimeError("tensorflow is not installed; cannot load TF model")
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


def _resolve_build_steps(args: argparse.Namespace, cfg: Dict[str, Any], backend: str) -> Dict[str, bool]:
    has_flag = any([args.csim, args.synth, args.cosim, args.export, args.bitfile, args.all])
    steps = _build_steps(cfg)
    if args.all:
        steps.update({"csim": True, "synth": True, "cosim": True, "export": True, "bitfile": True})
    elif has_flag:
        steps.update(
            {
                "csim": args.csim,
                "synth": args.synth,
                "cosim": args.cosim,
                "export": args.export,
                "bitfile": args.bitfile,
            }
        )
    if backend.lower() == "vitis" and steps["bitfile"]:
        # Vitis backend does not support bitfile; drop it instead of failing on --all
        steps["bitfile"] = False
    return steps


def _run_build_with_hls4ml(
    hls_model: Any, steps: Dict[str, bool], backend: str, extra_build_args: Dict[str, Any]
) -> None:
    build_kwargs = {
        "csim": steps["csim"],
        "synth": steps["synth"],
        "cosim": steps["cosim"],
        "export": steps["export"],
    }
    if backend.lower() != "vitis":
        build_kwargs["bitfile"] = steps["bitfile"]
    build_kwargs.update(extra_build_args)
    hls_model.build(**build_kwargs)


def _patch_vitis_tcl(build_tcl: Path, enabled: bool) -> None:
    if not enabled or not build_tcl.exists():
        return
    lines = build_tcl.read_text().splitlines()
    lines = [ln for ln in lines if "config_array_partition -maximum_size" not in ln]
    build_tcl.write_text("\n".join(lines) + "\n")


def _run_build_with_tool(build_tcl: Path, backend: str, runner: str, out_dir: Path) -> None:
    if backend.lower() != "vitis":
        subprocess.run([runner, "-f", str(build_tcl)], cwd=str(out_dir), check=True)
        return
    if runner == "vitis-run":
        cmd = [runner, "--mode", "hls", "--tcl", str(build_tcl)]
    else:
        cmd = [runner, "-f", str(build_tcl)]
    subprocess.run(cmd, cwd=str(out_dir), check=True)


def _resolve_synth_report_path(hls_dir: Path, suffix: str) -> Path | None:
    project_tcl = hls_dir / "project.tcl"
    if not project_tcl.exists():
        return None
    project_name = None
    backend_name = None
    top_name = None
    for line in project_tcl.read_text().splitlines():
        if "set project_name" in line:
            project_name = line.split('"')[-2]
        if "set backend" in line:
            backend_name = line.split('"')[-2]
        if "set_top" in line:
            parts = line.strip().split()
            if len(parts) >= 2:
                top_name = parts[-1]
    if project_name is None:
        return None
    if top_name is None:
        top_name = project_name
    if backend_name and "accelerator" in backend_name:
        project_name = f"{project_name}_axi"
    prj_dir = hls_dir / f"{project_name}_prj"
    if not prj_dir.exists():
        return None
    for sol_dir in prj_dir.iterdir():
        if not sol_dir.is_dir():
            continue
        report_dir = sol_dir / "syn" / "report"
        if not report_dir.exists():
            continue
        if top_name:
            candidate = report_dir / f"{top_name}_csynth.{suffix}"
            if candidate.exists():
                return candidate
        candidate = report_dir / f"csynth.{suffix}"
        if candidate.exists():
            return candidate
        # Fallback: first csynth report in solution
        for rpt in report_dir.glob(f"*_csynth.{suffix}"):
            return rpt
    return None


def _plot_model(hls_model: Any, cfg: Dict[str, Any]) -> None:
    out_path = cfg.get("plot_model", "nn/outputs/hls4ml_model_structure.png")
    # hls_model.plot_model(
    hls4ml.utils.plot_model(
        hls_model,
        show_shapes=True,
        show_precision=True,
        to_file=str(Path(out_path).resolve()),
    )


def _write_model(hls_model: Any) -> None:
    hls_model.write()



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="YAML hls4ml config file")
    ap.add_argument("--build", action="store_true", help="Run HLS build with config defaults")
    ap.add_argument("--csim", action="store_true", help="Run C simulation only")
    ap.add_argument("--synth", action="store_true", help="Run synthesis only")
    ap.add_argument("--cosim", action="store_true", help="Run C/RTL cosim")
    ap.add_argument("--export", action="store_true", help="Export HLS IP")
    ap.add_argument("--bitfile", action="store_true", help="Generate bitfile (non-Vitis backends only)")
    ap.add_argument("--all", action="store_true", help="Run all build steps")
    ap.add_argument("--write-only", action="store_true", help="Only write hls4ml project files")
    ap.add_argument("--plot-model", action="store_true", help="Plot the hls4ml model topology")
    ap.add_argument("--report", action="store_true", help="Read HLS report only")
    ap.add_argument("--clean", action="store_true", help="Remove existing hls4ml project output_dir before running")
    compare_group = ap.add_mutually_exclusive_group()
    compare_group.add_argument("--compare", action="store_true", help="Run hls4ml vs PyTorch comparison")
    compare_group.add_argument("--no-compare", action="store_true", help="Disable comparison even if config enables it")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if args.write_only and (args.build or args.all or args.csim or args.synth or args.cosim or args.export or args.bitfile):
        raise ValueError("--write-only cannot be combined with build step flags")
    if args.write_only and args.plot_model:
        raise ValueError("--write-only cannot be combined with --plot-model")
    if args.report and (args.build or args.all or args.csim or args.synth or args.cosim or args.export or args.bitfile):
        raise ValueError("--report cannot be combined with build step flags")

    cfg = _load_config(args.config)
    model_cfg = cfg["model"]
    source = model_cfg.get("source", "pytorch")
    onnx_path = Path(model_cfg.get("onnx_path", "")).resolve()
    out_dir = Path(model_cfg["output_dir"]).resolve()

    if args.clean:
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)


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

    backend = cfg["hls4ml"].get("backend", "Vitis")
    build_requested = args.build or args.all or args.csim or args.synth or args.cosim or args.export or args.bitfile
    if args.write_only:
        build_requested = False

    # Emit project files unless user asked for plot-only (and no build requested)
    if not (args.plot_model and not build_requested):
        _write_model(hls_model)

    if args.plot_model or cfg["hls4ml"].get("plot_model", None):
        _plot_model(hls_model, cfg["hls4ml"])

    if build_requested:
        build_cfg = cfg.get("build", {}) or {}
        driver = build_cfg.get("driver", "hls4ml")
        build_tcl = out_dir / "build_prj.tcl"
        extra_build_args = build_cfg.get("extra", {}) or {}
        build_steps = _resolve_build_steps(args, cfg, backend)

        _patch_vitis_tcl(
            build_tcl, enabled=backend.lower() == "vitis" and cfg["hls4ml"].get("vitis_patch_array_partition", True)
        )

        if driver == "hls4ml":
            _run_build_with_hls4ml(hls_model, build_steps, backend, extra_build_args)
        else:
            runner = cfg["hls4ml"].get("vitis_runner", "vitis-run")
            _run_build_with_tool(build_tcl, backend, runner, out_dir)

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

    if args.report:
        try:
            report = hls4ml.report.parse_vivado_report(str(out_dir))
        except Exception as exc:
            raise RuntimeError(f"could not parse HLS report from {out_dir}: {exc}") from exc
        if not report or "CSynthesisReport" not in report:
            raise RuntimeError(
                "synthesis report not found. Run with --synth (or --all) and ensure the HLS "
                "project generated syn/report/*.xml."
            )
        report_cfg = cfg.get("report", {}) or {}
        rpt_path = _resolve_synth_report_path(out_dir, "rpt")
        xml_path = _resolve_synth_report_path(out_dir, "xml")
        if rpt_path:
            print(f"Synthesis report source: {rpt_path}")
        else:
            print(f"Synthesis report source: {out_dir}")
        if args.verbose and xml_path:
            print(f"Synthesis report XML: {xml_path}")
        if args.verbose and rpt_path and rpt_path.exists():
            print("---- Begin Synthesis Report (rpt) ----")
            print(rpt_path.read_text())
            print("---- End Synthesis Report (rpt) ----")
        out_json = report_cfg.get("out_json", "")
        if out_json:
            Path(out_json).write_text(json.dumps(report, indent=2))
        print(json.dumps(report["CSynthesisReport"], indent=2))

    predict_cfg = cfg.get("predict", {}) or {}
    compare_requested = args.compare or (predict_cfg.get("enable", False) and not args.no_compare)
    if compare_requested:
        compile_mod.compile_and_compare(hls_model, cfg)

    print(f"hls4ml project generated at: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
