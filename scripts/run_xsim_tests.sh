#!/usr/bin/env bash
set -euo pipefail
set -x

source ~/fpga/2025.2/Vivado/settings64.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/xsim"
LOG_DIR="$BUILD_DIR/logs"

rm -rf "$BUILD_DIR"
mkdir -p "$LOG_DIR"
cd "$BUILD_DIR"

{
  echo "DATE: $(date)"
  echo "HOST: $(hostname)"
  echo "PWD: $(pwd)"
  echo "XILINX_VIVADO: ${XILINX_VIVADO:-}"
  command -v xsim
  xsim --version || true
  command -v xvhdl
  xvhdl --version || true
  command -v xelab
  xelab --version || true
} > "$LOG_DIR/env.log" 2>&1

run_tb() {
  local name="$1"
  shift
  local sources=("$@")

  local test_dir="$BUILD_DIR/$name"
  rm -rf "$test_dir"
  mkdir -p "$test_dir"
  cd "$test_dir"

  rm -rf xsim.dir work

  xvhdl -2008 -work work "${sources[@]}" 2>&1 | tee "$LOG_DIR/${name}_xvhdl.log"
  xelab -debug typical -top "$name" 2>&1 | tee "$LOG_DIR/${name}_xelab.log"

  # xsim resolves xsim.dir relative to the current working directory; run inside test_dir
  # so it can find the snapshot child executable (xsimk) and avoid "child exe not found".
  xsim "work.$name" -R 2>&1 | tee "$LOG_DIR/${name}_xsim.log"

  cd "$BUILD_DIR"
}

run_tb tb_stream_fifo \
  "$ROOT_DIR/rtl/pkg/common_pkg.vhd" \
  "$ROOT_DIR/rtl/stream/stream_fifo.vhd" \
  "$ROOT_DIR/sim/tb/tb_stream_fifo.vhd"

run_tb tb_width_conv \
  "$ROOT_DIR/rtl/stream/width_conv/byte_to_word.vhd" \
  "$ROOT_DIR/rtl/stream/width_conv/word_to_byte.vhd" \
  "$ROOT_DIR/sim/tb/tb_width_conv.vhd"

run_tb tb_pkt_rx_tx \
  "$ROOT_DIR/rtl/pkg/pkt_pkg.vhd" \
  "$ROOT_DIR/rtl/protocol/crc16.vhd" \
  "$ROOT_DIR/rtl/protocol/pkt_tx.vhd" \
  "$ROOT_DIR/rtl/protocol/pkt_rx.vhd" \
  "$ROOT_DIR/sim/tb/tb_pkt_rx_tx.vhd"
