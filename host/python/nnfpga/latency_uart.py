#!/usr/bin/env python3
"""
Measure inference latency in cycles using UART STATUS counters.
Uses exact same packet format as `proto.py`.

Workflow:
1) Send STATUS_REQ and capture counters (cycles, infers).
2) Send INFER_REQ (from a hex fixture like sim/fixtures/nn_in.hex).
3) Send STATUS_REQ again and compute delta cycles per inference.

Example:
  python host/python/nnfpga/latency_uart.py --port /dev/ttyUSB0 \
    --req sim/fixtures/nn_in.hex
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import List

import sys

PKG_ROOT = Path(__file__).resolve().parents[1]  # host/python
if str(PKG_ROOT) not in sys.path:
    sys.path.insert(0, str(PKG_ROOT))

from nnfpga import proto


@dataclass
class Status:
    build_id: int
    cycles: int
    stalls: int
    infers: int
    nn_data_w: int
    nn_frac_w: int


def _load_hex_bytes(path: Path) -> bytes:
    data: List[int] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data.append(int(line, 16) & 0xFF)
    return bytes(data)


def _read_exact(ser, n: int, timeout_s: float) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if not chunk:
            raise TimeoutError(f"UART timeout while reading {n} bytes (got {len(buf)})")
        buf.extend(chunk)
    return bytes(buf)


def _read_packet(ser, timeout_s: float, crc: bool) -> bytes:
    hdr = _read_exact(ser, 6, timeout_s)
    length = int.from_bytes(hdr[4:6], "big")
    payload = _read_exact(ser, length, timeout_s)
    tail = b""
    if crc:
        tail = _read_exact(ser, 2, timeout_s)
    return hdr + payload + tail


def _parse_status(payload: bytes) -> Status:
    if len(payload) < 20:
        raise ValueError(f"STATUS payload too short: {len(payload)} bytes")
    build_id = int.from_bytes(payload[0:4], "little")
    cycles = int.from_bytes(payload[4:8], "little")
    stalls = int.from_bytes(payload[8:12], "little")
    infers = int.from_bytes(payload[12:16], "little")
    nn_data_w = int.from_bytes(payload[16:18], "little")
    nn_frac_w = int.from_bytes(payload[18:20], "little")
    return Status(build_id, cycles, stalls, infers, nn_data_w, nn_frac_w)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="UART device (e.g., /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200, help="UART baud rate")
    ap.add_argument("--req", required=True, help="Hex file for INFER_REQ packet")
    ap.add_argument("--timeout", type=float, default=2.0, help="Read timeout in seconds")
    ap.add_argument("--crc", action="store_true", help="Expect CRC in packets")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    try:
        import serial  # type: ignore
    except Exception as exc:  # pragma: no cover - environment-dependent
        raise RuntimeError("pyserial is required (pip install pyserial)") from exc

    infer_req = _load_hex_bytes(Path(args.req))
    status_req = proto.pack_packet(proto.STATUS_REQ, b"", crc=args.crc)

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        # STATUS before
        ser.write(status_req)
        ser.flush()
        rsp_before = _read_packet(ser, args.timeout, args.crc)
        pkt_before = proto.unpack_packet(rsp_before, crc=args.crc)
        status_before = _parse_status(pkt_before.payload)

        # INFER
        ser.write(infer_req)
        ser.flush()
        _ = _read_packet(ser, args.timeout, args.crc)

        # STATUS after
        ser.write(status_req)
        ser.flush()
        rsp_after = _read_packet(ser, args.timeout, args.crc)
        pkt_after = proto.unpack_packet(rsp_after, crc=args.crc)
        status_after = _parse_status(pkt_after.payload)

    delta_cycles = status_after.cycles - status_before.cycles
    delta_infers = status_after.infers - status_before.infers
    if delta_infers <= 0:
        print("No new inferences counted; cannot compute latency.")
        return 1

    latency_cycles = delta_cycles // delta_infers
    print(f"Inferences: {delta_infers}")
    print(f"Delta cycles: {delta_cycles}")
    print(f"Latency (cycles per inference): {latency_cycles}")

    if args.verbose:
        print(f"Status before: {status_before}")
        print(f"Status after : {status_after}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
