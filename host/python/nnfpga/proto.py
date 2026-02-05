"""Packet format reference used by pkt_tx/pkt_rx."""

from __future__ import annotations

from dataclasses import dataclass

MAGIC = 0xA55A
VERSION = 0x01

STATUS_REQ = 0x01
STATUS_RSP = 0x81
INFER_REQ = 0x02
INFER_RSP = 0x82


def crc16_ccitt(data: bytes, init: int = 0xFFFF) -> int:
    """CRC-16/CCITT-FALSE, MSB-first, poly 0x1021, no xorout."""
    crc = init & 0xFFFF
    for b in data:
        for i in range(8):
            bit = (b >> (7 - i)) & 1
            c15 = (crc >> 15) & 1
            crc = ((crc << 1) & 0xFFFF)
            if c15 ^ bit:
                crc ^= 0x1021
    return crc & 0xFFFF


@dataclass
class Packet:
    pkt_type: int
    payload: bytes


def pack_packet(pkt_type: int, payload: bytes, crc: bool = False) -> bytes:
    length = len(payload)
    header = MAGIC.to_bytes(2, "big") + bytes([VERSION, pkt_type]) + length.to_bytes(2, "big")
    body = header + payload
    if crc:
        crc_val = crc16_ccitt(body[2:])  # version..payload
        body += crc_val.to_bytes(2, "big")
    return body


def unpack_packet(data: bytes, crc: bool = False) -> Packet:
    if len(data) < 6:
        raise ValueError("packet too short")
    if int.from_bytes(data[0:2], "big") != MAGIC:
        raise ValueError("bad magic")
    if data[2] != VERSION:
        raise ValueError("bad version")
    pkt_type = data[3]
    length = int.from_bytes(data[4:6], "big")
    expected = 6 + length + (2 if crc else 0)
    if len(data) < expected:
        raise ValueError("truncated packet")
    payload = data[6 : 6 + length]
    if crc:
        crc_rx = int.from_bytes(data[6 + length : 8 + length], "big")
        crc_calc = crc16_ccitt(data[2 : 6 + length])
        if crc_rx != crc_calc:
            raise ValueError("crc mismatch")
    return Packet(pkt_type=pkt_type, payload=payload)
