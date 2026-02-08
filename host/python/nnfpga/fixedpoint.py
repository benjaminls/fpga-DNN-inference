"""Fixed-point packing/unpacking reference for tensor_adapter."""

from __future__ import annotations

from typing import Iterable, List


def _limits(width: int, signed: bool) -> tuple[int, int]:
    if signed:
        return (-(1 << (width - 1)), (1 << (width - 1)) - 1)
    return (0, (1 << width) - 1)


def quantize(value: float, data_width: int = 16, frac_width: int = 10, signed: bool = True) -> int:
    """Quantize float to fixed-point integer with saturation."""
    scale = 1 << frac_width
    raw = int(round(value * scale))
    lo, hi = _limits(data_width, signed)
    return max(lo, min(hi, raw))


def _to_twos(value: int, width: int) -> int:
    if value < 0:
        value = (1 << width) + value
    return value & ((1 << width) - 1)


def pack_values(
    values: Iterable[float], data_width: int = 16, frac_width: int = 10, signed: bool = True
) -> bytes:
    """Pack iterable of floats into little-endian fixed-point bytes."""
    out = bytearray()
    for v in values:
        q = quantize(v, data_width=data_width, frac_width=frac_width, signed=signed)
        q_u = _to_twos(q, data_width)
        out.extend(int(q_u).to_bytes(data_width // 8, byteorder="little", signed=False))
    return bytes(out)


def unpack_ints(payload: bytes, data_width: int = 16, signed: bool = True) -> List[int]:
    """Unpack little-endian bytes into signed integers."""
    step = data_width // 8
    out: List[int] = []
    for i in range(0, len(payload), step):
        raw = int.from_bytes(payload[i : i + step], byteorder="little", signed=False)
        if signed and raw & (1 << (data_width - 1)):
            raw = raw - (1 << data_width)
        out.append(raw)
    return out


def unpack_values(payload: bytes, data_width: int = 16, frac_width: int = 10, signed: bool = True) -> List[float]:
    """Unpack little-endian bytes into floats."""
    scale = 1 << frac_width
    ints = unpack_ints(payload, data_width=data_width, signed=signed)
    return [v / scale for v in ints]
