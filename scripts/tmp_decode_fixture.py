"""Temporary helper to decode UART fixture payloads into floats.

Usage:
  PYTHONPATH=/home/user/workdir/fpga-DNN-inference \
  mamba run -p /home/user/.local/share/mamba/envs/nnfpga \
  python scripts/tmp_decode_fixture.py --req sim/fixtures/nn_in.hex --rsp sim/fixtures/uart_last_rsp.hex

This reads packet hex dumps (one byte per line), decodes the payload using the
same fixed-point settings as the RTL, and prints the float values.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from host.python.nnfpga import fixedpoint, proto


def _read_hex_bytes(path: Path) -> bytes:
    data = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        data.append(int(s, 16))
    return bytes(data)


def _decode_pkt(path: Path) -> list[float]:
    pkt_bytes = _read_hex_bytes(path)
    pkt = proto.unpack_packet(pkt_bytes, crc=False)
    return fixedpoint.unpack_values(pkt.payload)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--req", help="Path to INFER_REQ hex file (nn_in.hex)")
    ap.add_argument("--rsp", help="Path to INFER_RSP hex file (nn_out.hex or uart_last_rsp.hex)")
    args = ap.parse_args()

    if args.req:
        vals = _decode_pkt(Path(args.req))
        print(f"REQ payload values ({len(vals)}): {vals}")

    if args.rsp:
        vals = _decode_pkt(Path(args.rsp))
        print(f"RSP payload values ({len(vals)}): {vals}")

    if not args.req and not args.rsp:
        ap.error("Provide --req and/or --rsp")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
