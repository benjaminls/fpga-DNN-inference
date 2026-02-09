#!/usr/bin/env python3
"""
UART packet sender/receiver for NN FPGA inference validation.

This script is the bridge between the software "golden" fixtures and the
hardware UART path. It takes a prebuilt INFER_REQ (or STATUS_REQ) packet
encoded as hex bytes (one byte per line), sends it over UART, reads back
the full response packet, and optionally compares the result against an
expected hex fixture. This is the hardware validation step for Milestone 9:

1) Generate golden fixtures:
   python sim/models/nn_golden.py --config nn/configs/calhouse.yaml \
     --checkpoint nn/outputs/calhouse/default/model.pt
2) Program the FPGA with the RTL + hls4ml core.
3) Run this script:
   python host/python/nnfpga/send_uart.py --port /dev/ttyUSB0 \
     --req sim/fixtures/nn_in.hex --expect sim/fixtures/nn_out.hex

If the response matches the expected bytes, we have verified that the
hardware UART path and the integrated hls4ml core are producing the
same results as the golden PyTorch model.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List

import sys

PKG_ROOT = Path(__file__).resolve().parents[1]  # host/python
if str(PKG_ROOT) not in sys.path:
    sys.path.insert(0, str(PKG_ROOT))

from nnfpga import proto


def _load_hex_bytes(path: Path) -> bytes:
    data: List[int] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data.append(int(line, 16) & 0xFF)
    return bytes(data)


def _save_hex_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for b in data:
            f.write(f"{b:02X}\n")


def _read_exact(ser, n: int, timeout_s: float) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if not chunk:
            # pyserial returns b'' on timeout
            raise TimeoutError(f"UART timeout while reading {n} bytes (got {len(buf)})")
        buf.extend(chunk)
    return bytes(buf)


def _read_packet(ser, timeout_s: float, crc: bool) -> bytes:
    # Header is 6 bytes: magic(2) + version + type + length(2)
    hdr = _read_exact(ser, 6, timeout_s)
    length = int.from_bytes(hdr[4:6], "big")
    payload = _read_exact(ser, length, timeout_s)
    tail = b""
    if crc:
        tail = _read_exact(ser, 2, timeout_s)
    return hdr + payload + tail


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="UART device (e.g., /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200, help="UART baud rate")
    ap.add_argument("--req", required=True, help="Hex file for request packet (one byte per line)")
    ap.add_argument("--expect", default="", help="Optional hex file for expected response packet")
    ap.add_argument("--out", default="sim/fixtures/uart_last_rsp.hex", help="Save response hex here")
    ap.add_argument("--timeout", type=float, default=2.0, help="Read timeout in seconds")
    ap.add_argument("--crc", action="store_true", help="Expect CRC in packets")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    try:
        import serial  # type: ignore
    except Exception as exc:  # pragma: no cover - environment-dependent
        raise RuntimeError("pyserial is required (pip install pyserial)") from exc

    req_path = Path(args.req)
    req_data = _load_hex_bytes(req_path)
    if args.verbose:
        print(f"Loaded {len(req_data)} request bytes from {req_path}")

    expect_data = b""
    expect_path = Path(args.expect) if args.expect else None
    if expect_path and expect_path.exists():
        expect_data = _load_hex_bytes(expect_path)
        if args.verbose:
            print(f"Loaded {len(expect_data)} expected bytes from {expect_path}")

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(req_data)
        ser.flush()

        rsp_data = _read_packet(ser, args.timeout, args.crc)

    out_path = Path(args.out)
    _save_hex_bytes(out_path, rsp_data)
    print(f"Wrote response to {out_path}")

    # Basic sanity check
    try:
        pkt = proto.unpack_packet(rsp_data, crc=args.crc)
        if args.verbose:
            print(f"Response type: 0x{pkt.pkt_type:02X}, payload length: {len(pkt.payload)}")
    except Exception as exc:
        print(f"Warning: response packet parse failed: {exc}")

    if expect_data:
        if rsp_data != expect_data:
            print("Mismatch: response does not match expected bytes")
            return 1
        print("Match: response equals expected bytes")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
