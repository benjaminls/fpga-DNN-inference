#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC_DIR=${1:-"$ROOT_DIR/nn/outputs/calhouse/default/hls4ml/myproject_prj/solution1/impl/ip/hdl/verilog"}
DST_DIR="$ROOT_DIR/rtl/nn/generated"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DST_DIR"

# Copy only the top-level module and its dependencies
cp -v "$SRC_DIR"/myproject*.v "$DST_DIR"/
cp -v "$SRC_DIR"/myproject*.vh "$DST_DIR"/

echo "Synced HLS IP HDL to $DST_DIR"
