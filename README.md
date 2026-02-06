# fpga-DNN-inference

Pure-RTL (VHDL) NN inference pipeline targeting the Digilent Nexys Video.

## Quick Start
- Build bitstream (Vivado CLI):
  - `make build`

## Repo Layout
- `rtl/`: synthesizable VHDL
- `constraints/`: board constraints (XDC)
- `scripts/`: build/sim helpers
- `sim/`: testbenches and fixtures
- `host/python/`: host-side tooling
- `nn`: train DNN, generate hls4ml rtl
