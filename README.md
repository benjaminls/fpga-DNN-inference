# fpga-DNN-inference

Pure-RTL (VHDL) NN inference pipeline targeting the Digilent Nexys Video.

## Quick Start
- Build bitstream (Vivado CLI):
  - `make build`
- Program FPGA (Vivado CLI):
  - `vivado -mode batch -source scripts/program_fpga.tcl`
  - or pass a specific bitfile: `vivado -mode batch -source scripts/program_fpga.tcl -tclargs /path/to.bit`


## Repo Layout
- `rtl/`: synthesizable VHDL
- `constraints/`: board constraints (XDC)
- `scripts/`: build/sim helpers
- `sim/`: testbenches and fixtures
- `host/python/`: host-side tooling
- `nn`: train DNN, generate hls4ml rtl


## UART Debugging Notes
We hit a UART bring-up issue where the FPGA would not respond to STATUS requests. The key lessons:

1) **LED meaning matters**: LD13/LD12 indicate PC->board and board->PC traffic, not raw FPGA RX/TX. Seeing TX blink without RX does not guarantee the UART path is parsing packets.
2) **On-board FT232R wiring**: The Nexys Video USB-UART bridge (J13) uses V18 (uart_tx_in, PC->FPGA) and AA19 (uart_rx_out, FPGA->PC). These must match the `uart_rx`/`uart_tx` pins in the XDC.
3) **UART RX verified**: We added temporary LED instrumentation in `rtl/top/top_nexys_video.vhd`:
   - `led(6)` mirrors the raw `uart_rx` pin (idle high)
   - `led(7)` toggles on each `rx_valid` pulse
4) **Root cause**: The top-level only responded to `INFER_REQ`, so `STATUS_REQ` never produced a response. Fixing this by integrating `mmio_status` + `perf_counters` in `top_nexys_video.vhd` made STATUS return correctly.

Rebuild and reprogram commands:
```bash
vivado -mode batch -source scripts/build_vivado.tcl &&                                     
vivado -mode batch -source scripts/program_fpga.tcl
```

Send STATUS (`--status`) protocol packet using command:
```bash
python host/python/nnfpga/send_uart.py --port /dev/ttyUSB0 --status --verbose --baud 115200
```
Output:
```
Using STATUS_REQ packet
Wrote response to sim/fixtures/uart_last_rsp.hex
Response type: 0x81, payload length: 20
```

Once the STATUS path returned a valid packet (`0x81` with 20-byte payload), UART bring-up was confirmed and we proceeded to INFER tests. 

We sent a real STATUS_REQ packet (type 0x01) using the same header/format as the inference packets, but make no mistake, it is not inference. It's a real protocol request and exercises the UART + packet parsing + response path.
