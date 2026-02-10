# RTL Development Notes

This README captures the current RTL edit -> deploy workflow.

## RTL Edit -> FPGA Deploy (Current Workflow)
If you edited RTL under `rtl/` and want to deploy to the FPGA, run:

1. **(If the NN/hls4ml core or weights changed)** rebuild + resync the HLS IP:
```bash
python nn/scripts/run_hls4ml.py --config nn/hls4ml_config.yaml --clean --all
scripts/sync_hls4ml_ip.sh
```

2. **Build the FPGA bitstream:**
```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

3. **Program the FPGA:**
```bash
vivado -mode batch -source scripts/program_fpga.tcl
```

## Optional Sanity Checks
Check STATUS path (UART is alive):
```bash
python host/python/nnfpga/send_uart.py --port /dev/ttyUSB0 --status --verbose --baud 115200
```

Run inference vs golden fixtures:
```bash
python host/python/nnfpga/send_uart.py \
  --port /dev/ttyUSB0 \
  --req sim/fixtures/nn_in.hex \
  --expect sim/fixtures/nn_out.hex \
  --baud 115200
```
