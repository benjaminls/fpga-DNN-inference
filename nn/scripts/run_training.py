#!/usr/bin/env python3
"""Run a training experiment from YAML config."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import numpy as np

from nn.datasets import calhouse
from nn.export import hls4ml_stub, onnx_export
from nn.metrics import regression
from nn.models import mlp_regressor
from nn.plots import loss_curves, parity_plot
from nn.train import eval as eval_mod
from nn.train import train_loop
from nn.utils import config as config_mod
from nn.utils import io, seed


def print_sample_summary(sample: np.ndarray, name: str) -> None:
    print(f"{name} shape: {sample.shape}")
    print(f"{name} dtype: {sample.dtype}")
    print(f"{name} mean: {np.mean(sample):.4f}, std: {np.std(sample):.4f}")
    print(f"{name} min: {np.min(sample):.4f}, max: {np.max(sample):.4f}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    cfg = config_mod.load_config(args.config)
    seed.set_seed(cfg["training"]["seed"])

    print(f"config: {args.config}")
    if args.verbose:
        print(cfg)

    X_train, y_train, X_val, y_val, X_test, y_test, xscaler, yscaler = calhouse.load_dataset(cfg)
    if args.verbose:
        print_sample_summary(X_train, "X_train")
        print_sample_summary(y_train, "y_train")
        print_sample_summary(X_val, "X_val")
        print_sample_summary(y_val, "y_val")
        print_sample_summary(X_test, "X_test")
        print_sample_summary(y_test, "y_test")


    model = mlp_regressor.build_mlp(
        input_dim=X_train.shape[1],
        hidden=cfg["model"]["hidden"],
        dropout=cfg["model"]["dropout"],
    )

    # Save model diagram (requires torchview + graphviz)
    try:
        from torchview import draw_graph

        graph = draw_graph(
            model,
            input_size=(1, X_train.shape[1]),
            expand_nested=True,
            graph_name="mlp_regressor",
        )
        out_dir = io.ensure_dir(cfg["outputs"]["dir"])
        graph.visual_graph.render(
            filename=str(out_dir / "model_diagram"), format="png", cleanup=True
        )
    except Exception as exc:
        raise RuntimeError(
            "Model diagram generation failed. Install torchview and graphviz "
            "(and ensure Graphviz binaries are available on PATH)."
        ) from exc

    model, train_losses, val_losses = train_loop.run_train(
        model, (X_train, y_train), (X_val, y_val), cfg
    )

    metrics = eval_mod.run_eval(model, (X_test, y_test))

    out_dir = io.ensure_dir(cfg["outputs"]["dir"])
    print(f"outputs: {out_dir}")
    io.save_json(out_dir / "metrics.json", metrics)
    io.save_json(
        out_dir / "model_info.json",
        {"input_dim": int(X_train.shape[1]), "hidden": cfg["model"]["hidden"]},
    )

    loss_curves.plot_loss(train_losses, val_losses, out_dir / "loss_curves.png")

    # Parity plot from test set
    model.eval()
    import torch

    with torch.no_grad():
        preds = model(torch.from_numpy(X_test).float()).numpy().squeeze()
    parity_plot.plot_parity(y_test, preds, out_dir / "parity.png")

    # Save predictions
    io.save_numpy(out_dir / "y_test.npy", y_test)
    io.save_numpy(out_dir / "y_test_pred.npy", preds)

    # Save scalers
    io.save_scalers(
        out_dir / "scalers.npy",
        {"xscaler": xscaler, "yscaler": yscaler},
    )


    if cfg["export"].get("onnx", False):
        onnx_export.export_onnx(model, X_train.shape[1], out_dir / "model.onnx")

    if cfg["export"].get("hls4ml_stub", False):
        hls4ml_stub.emit_stub(out_dir / "model.onnx", out_dir / "hls4ml_config.yaml")

    # Save PyTorch weights for hls4ml PyTorch frontend
    torch.save(model.state_dict(), out_dir / "model.pt")

    print(f"metrics: {metrics}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
