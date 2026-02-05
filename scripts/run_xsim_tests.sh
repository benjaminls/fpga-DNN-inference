#!/usr/bin/env bash
set -euo pipefail

source ~/fpga/2025.2/Vivado/settings64.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/xsim"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

run_tb() {
  local name="$1"
  shift
  local sources=("$@")

  rm -rf xsim.dir work

  xvhdl -2008 -work work "${sources[@]}"
  xelab -debug typical -top "$name"
  xsim "work.$name" -R
}

run_tb tb_stream_fifo \
  "$ROOT_DIR/rtl/pkg/common_pkg.vhd" \
  "$ROOT_DIR/rtl/stream/stream_fifo.vhd" \
  "$ROOT_DIR/sim/tb/tb_stream_fifo.vhd"

run_tb tb_width_conv \
  "$ROOT_DIR/rtl/stream/width_conv/byte_to_word.vhd" \
  "$ROOT_DIR/rtl/stream/width_conv/word_to_byte.vhd" \
  "$ROOT_DIR/sim/tb/tb_width_conv.vhd"
