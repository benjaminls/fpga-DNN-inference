"""Utilities to compile an hls4ml model and compare with PyTorch."""

# TODO: Language assumes pytorch only, add more abstraction for TF, onnx, etc.

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Tuple

import json

import numpy as np
import matplotlib.pyplot as plt
import torch

from nn.datasets import calhouse
from nn.metrics import regression
from nn.models import mlp_regressor
from nn.utils import config as config_mod
from nn.utils import io


def _load_test_data(training_config: str | Path) -> Tuple[np.ndarray, np.ndarray]:
    cfg = config_mod.load_config(training_config)
    _, _, _, _, X_test, y_test, _, _ = calhouse.load_dataset(cfg)
    return X_test, y_test


def _load_pytorch_model(model_cfg: Dict[str, Any]) -> torch.nn.Module:
    pt_cfg = model_cfg["pytorch"]
    checkpoint = Path(pt_cfg["checkpoint"]).resolve()
    info_path = pt_cfg.get("model_info", "")
    input_dim = int(pt_cfg.get("input_dim", 0))
    hidden = pt_cfg.get("hidden", [])
    dropout = float(pt_cfg.get("dropout", 0.0))

    if info_path:
        info = json.loads(Path(info_path).read_text())
        input_dim = int(info.get("input_dim", input_dim))
        hidden = info.get("hidden", hidden)

    model = mlp_regressor.build_mlp(input_dim=input_dim, hidden=hidden, dropout=dropout)
    model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    model.eval()
    return model


def _predict_pytorch(model: torch.nn.Module, X_test: np.ndarray) -> np.ndarray:
    with torch.no_grad():
        preds = model(torch.from_numpy(X_test).float()).numpy().squeeze()
    return preds


def _plot_parity(
        y_true: np.ndarray, 
        y_pred: np.ndarray, 
        out_path: Path, 
        title: str,
    ) -> None:
    plt.figure(figsize=(5, 5))
    plt.scatter(y_true, y_pred, s=8, alpha=0.6)
    lo = float(min(np.min(y_true), np.min(y_pred)))
    hi = float(max(np.max(y_true), np.max(y_pred)))
    plt.plot([lo, hi], [lo, hi], "k--", linewidth=1)
    plt.title(title)
    plt.xlabel("True")
    plt.ylabel("Predicted")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def _plot_residual_hist(
        y_true: np.ndarray, 
        y_pred: np.ndarray, 
        out_path: Path, 
        title: str,
        log: bool = False,
    ) -> None:
    residual = y_pred - y_true
    plt.figure(figsize=(5, 4))
    plt.hist(residual, bins=40, alpha=0.7, color="tab:blue", log=log)
    plt.title(title)
    plt.xlabel("Residual")
    plt.ylabel("Count")
    if log:
        plt.yscale("log")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def _plot_pull(
        y_true: np.ndarray, 
        y_pred: np.ndarray, 
        out_path: Path, 
        title: str,
        log: bool = False,
    ) -> None:
    residual = y_pred - y_true
    sigma = float(np.std(residual)) if np.std(residual) > 0 else 1.0
    pull = residual / sigma
    plt.figure(figsize=(5, 4))
    plt.hist(pull, bins=40, alpha=0.7, color="tab:green", log=log)
    plt.title(title)
    plt.xlabel("Pull (residual / sigma)")
    plt.ylabel("Count")
    if log:
        plt.yscale("log")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def _plot_pull_compare(
    y_true: np.ndarray,
    y_pytorch: np.ndarray,
    y_hls: np.ndarray,
    out_path: Path,
    title: str,
    log: bool = False,
) -> None:
    res_pt = y_pytorch - y_true
    res_hls = y_hls - y_true
    sigma_pt = float(np.std(res_pt)) if np.std(res_pt) > 0 else 1.0
    sigma_hls = float(np.std(res_hls)) if np.std(res_hls) > 0 else 1.0
    pull_pt = res_pt / sigma_pt
    pull_hls = res_hls / sigma_hls

    plt.figure(figsize=(5, 4))
    plt.hist(pull_pt, bins=40, histtype="step", linewidth=1.5, label="PyTorch", log=log)
    plt.hist(pull_hls, bins=40, histtype="step", linewidth=1.5, label="HLS", log=log)
    plt.title(title)
    plt.xlabel("Pull (residual / sigma)")
    plt.ylabel("Count")
    if log:
        plt.yscale("log")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def _plot_pred_compare(
    y_pytorch: np.ndarray,
    y_hls: np.ndarray,
    out_path: Path,
    title: str,
) -> None:
    plt.figure(figsize=(5, 5))
    plt.scatter(y_pytorch, y_hls, s=8, alpha=0.6)
    lo = float(min(np.min(y_pytorch), np.min(y_hls)))
    hi = float(max(np.max(y_pytorch), np.max(y_hls)))
    plt.plot([lo, hi], [lo, hi], "k--", linewidth=1)
    plt.title(title)
    plt.xlabel("PyTorch prediction")
    plt.ylabel("HLS prediction")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def _compute_metrics(y_true: np.ndarray, y_pred: np.ndarray) -> Dict[str, float]:
    return {
        "mae": regression.mae(y_true, y_pred),
        "rmse": regression.rmse(y_true, y_pred),
        "r2": regression.r2(y_true, y_pred),
    }


def compile_and_compare(hls_model: Any, cfg: Dict[str, Any]) -> Dict[str, Dict[str, float]]:
    """Compile hls4ml model, run inference, and compare with PyTorch."""
    predict_cfg = cfg.get("predict", {}) or {}
    training_config = predict_cfg.get("training_config")
    if not training_config:
        raise ValueError("predict.training_config is required to load test data")

    out_dir: Path = io.ensure_dir(Path(cfg["model"]["output_dir"]) / "plots")
    X_test, y_test = _load_test_data(training_config)

    # hls4ml recommended flow for inference
    hls_model.compile()
    X_test = np.ascontiguousarray(X_test)
    y_hls = np.asarray(hls_model.predict(X_test)).squeeze()

    # PyTorch baseline
    pt_model = _load_pytorch_model(cfg["model"])
    y_pt: np.ndarray = _predict_pytorch(pt_model, X_test)

    # Metrics and comparisons
    hls_metrics = _compute_metrics(y_test, y_hls)
    pt_metrics = _compute_metrics(y_test, y_pt)
    delta = {k: hls_metrics[k] - pt_metrics[k] for k in hls_metrics}
    summary = {"hls": hls_metrics, "pytorch": pt_metrics, "delta": delta}

    io.save_json(out_dir / "hls_metrics.json", hls_metrics)
    io.save_json(out_dir / "pytorch_metrics.json", pt_metrics)
    io.save_json(out_dir / "compare_metrics.json", summary)

    io.save_numpy(out_dir / "y_test_hls.npy", y_hls)
    io.save_numpy(out_dir / "y_test_pytorch.npy", y_pt)

    # Plots suited for regression
    _plot_parity(y_test, y_hls, out_dir / "parity_hls.png", "Parity: HLS vs True")
    _plot_parity(y_test, y_pt, out_dir / "parity_pytorch.png", "Parity: PyTorch vs True")
    _plot_residual_hist(y_test, y_hls, out_dir / "residuals_hls.png", "Residuals: HLS")
    _plot_residual_hist(y_test, y_pt, out_dir / "residuals_pytorch.png", "Residuals: PyTorch")
    _plot_residual_hist(y_test, y_hls, out_dir / "residuals_hls_log.png", "Residuals: HLS", log=True)
    _plot_residual_hist(y_test, y_pt, out_dir / "residuals_pytorch_log.png", "Residuals: PyTorch", log=True)
    _plot_pull(y_test, y_hls, out_dir / "pull_hls.png", "Pull: HLS")
    _plot_pull(y_test, y_pt, out_dir / "pull_pytorch.png", "Pull: PyTorch")
    _plot_pull(y_test, y_pt, out_dir / "pull_pytorch_log.png", "Pull: PyTorch", log=True)
    _plot_pull(y_test, y_hls, out_dir / "pull_hls_log.png", "Pull: HLS", log=True)
    _plot_pull_compare(y_test, y_pt, y_hls, out_dir / "pull_compare.png", "Pull: PyTorch vs HLS")
    _plot_pull_compare(y_test, y_pt, y_hls, out_dir / "pull_compare_log.png", "Pull: PyTorch vs HLS", log=True)
    _plot_pred_compare(y_pt, y_hls, out_dir / "pred_compare.png", "HLS vs PyTorch")

    print("HLS metrics:", hls_metrics)
    print("PyTorch metrics:", pt_metrics)
    print("Delta (HLS - PyTorch):", delta)

    return summary
