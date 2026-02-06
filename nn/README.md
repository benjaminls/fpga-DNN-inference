# NN Training Pipeline

This folder contains a small, config-driven PyTorch pipeline used to train a model for hls4ml export.
It handles parsing, preprocessing, training, evaluation, plotting, and export artifacts.

## Quick Start
Run training for California Housing (calhouse):

```bash
python nn/scripts/run_training.py --config nn/configs/calhouse.yaml
```

If you use the `nnfpga` mamba env:

```bash
PYTHONPATH=/home/user/workdir/fpga-DNN-inference \
mamba run -p /home/user/.local/share/mamba/envs/nnfpga \
python nn/scripts/run_training.py --config nn/configs/calhouse.yaml
```

Outputs are written to `nn/outputs/calhouse/default/` by default.

## Organization
- `nn/configs/`: YAML experiment configs (dataset/model/training/exports)
- `nn/datasets/`: dataset loaders (zip parsing, splits, normalization)
- `nn/models/`: PyTorch model definitions
- `nn/train/`: training loop and evaluation helpers
- `nn/metrics/`: regression metrics (MAE, RMSE, R2)
- `nn/plots/`: loss curves + parity plots
- `nn/export/`: ONNX export + hls4ml config stub
- `nn/scripts/`: CLI entrypoints
- `nn/tests/`: unit tests for parsing, metrics, export stub

## Artifacts
A typical run produces:
- `metrics.json`
- `loss_curves.png`
- `parity.png`
- `model_diagram.png`
- `model.onnx`
- `hls4ml_config.yaml`
- `model.pt`
- `model_info.json`

## Notes
- The calhouse loader drops rows with missing values to avoid NaNs.
- Feature/target columns are configured in `nn/configs/calhouse.yaml`.
- Model diagram generation requires `torchview` and Graphviz binaries.

## hls4ml Export
An example config lives at `nn/hls4ml_config.yaml`.

Generate an hls4ml project from ONNX or PyTorch:

```bash
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml
```

Run the full HLS flow (C sim + synth + export), using hls4ml's build helpers:

```bash
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --build
```

Optionally compile the hls4ml model and compare predictions with PyTorch:

```bash
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --compare
```

Run a single build step (overrides config defaults):

```bash
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --csim
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --synth
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --all
```

Key YAML knobs:
- `model.source` (`onnx` or `pytorch`)
- `hls4ml.reuse_factor`
- `hls4ml.precision`
- `hls4ml.strategy`
- `hls4ml.layer_precision` / `hls4ml.layer_reuse`
- `hls4ml.backend`, `hls4ml.part`, `hls4ml.clock_period`, `hls4ml.io_type`
- `build.driver` (`hls4ml`, `vitis-run`, `vitis_hls`)
- `build.csim` / `build.synth` / `build.cosim` / `build.export` / `build.bitfile`
- `build.extra` (optional dict of additional `hls_model.build(...)` kwargs)
- `report.enable` and `report.out_json`
- `predict.enable` and `predict.training_config`
