# Simulation Fixtures

Generate golden packet fixtures for the real hls4ml core (recommended for HW comparison):

```bash
python sim/models/nn_golden.py \
  --config nn/configs/calhouse.yaml \
  --checkpoint nn/outputs/calhouse/default/model.pt \
  --use-hls4ml
```

This writes:
- `sim/fixtures/nn_in.hex`
- `sim/fixtures/nn_out.hex`

`tb_top_e2e.vhd` uses these files to validate the real hls4ml core output.

If you omit `--use-hls4ml`, the output is generated from the PyTorch model
and may not exactly match the fixed-point hls4ml hardware.
