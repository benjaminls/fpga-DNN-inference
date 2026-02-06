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

Key YAML knobs:
- `model.source` (`onnx` or `pytorch`)
- `hls4ml.reuse_factor`
- `hls4ml.precision`
- `hls4ml.strategy`
- `hls4ml.layer_precision` / `hls4ml.layer_reuse`
- `hls4ml.backend`, `hls4ml.part`, `hls4ml.clock_period`, `hls4ml.io_type`
