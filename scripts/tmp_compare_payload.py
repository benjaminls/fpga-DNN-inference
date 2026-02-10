"""Temporary helper to compare PyTorch vs hls4ml predictions for a request payload.

Usage:
  PYTHONPATH=/home/user/workdir/fpga-DNN-inference \
  mamba run -p /home/user/.local/share/mamba/envs/nnfpga \
  python scripts/tmp_compare_payload.py \
    --req sim/fixtures/nn_in.hex \
    --expect sim/fixtures/nn_out.hex \
    --actual sim/fixtures/uart_last_rsp.hex \
    --hls-config nn/hls4ml_config.yaml
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from host.python.nnfpga import fixedpoint, proto
from nn.models import mlp_regressor
from nn.utils import config as config_mod


def _read_hex_bytes(path: Path) -> bytes:
    data = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        data.append(int(s, 16))
    return bytes(data)


def _decode_payload(path: Path) -> list[float]:
    pkt_bytes = _read_hex_bytes(path)
    pkt = proto.unpack_packet(pkt_bytes, crc=False)
    return fixedpoint.unpack_values(pkt.payload)

def _decode_payload_ints(path: Path) -> list[int]:
    pkt_bytes = _read_hex_bytes(path)
    pkt = proto.unpack_packet(pkt_bytes, crc=False)
    return fixedpoint.unpack_ints(pkt.payload, signed=True)


def _pretty_bytes(payload: bytes) -> str:
    return " ".join(f"{b:02X}" for b in payload)


def _build_pytorch_model(cfg: dict) -> "torch.nn.Module":
    import torch

    m = cfg["model"]
    pt_cfg = m["pytorch"]
    hidden = pt_cfg.get("hidden", [])
    dropout = float(pt_cfg.get("dropout", 0.0))
    checkpoint = Path(pt_cfg["checkpoint"]).resolve()
    info_path = pt_cfg.get("model_info", "")

    if info_path:
        info_path = Path(info_path).resolve()
        info = json.loads(info_path.read_text())
        hidden = info.get("hidden", hidden)

    input_dim = int(pt_cfg.get("input_dim", 0))
    if info_path:
        input_dim = int(info.get("input_dim", input_dim))

    model = mlp_regressor.build_mlp(input_dim=input_dim, hidden=hidden, dropout=dropout)
    model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    model.eval()
    return model


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--req", required=True, help="INFER_REQ hex (nn_in.hex)")
    ap.add_argument("--expect", help="Expected INFER_RSP hex (nn_out.hex)")
    ap.add_argument("--actual", help="Actual INFER_RSP hex (uart_last_rsp.hex)")
    ap.add_argument("--hls-config", default="nn/hls4ml_config.yaml", help="hls4ml config yaml")
    args = ap.parse_args()

    req_bytes = _read_hex_bytes(Path(args.req))
    req_pkt = proto.unpack_packet(req_bytes, crc=False)
    ints = fixedpoint.unpack_ints(req_pkt.payload, signed=True)
    x = fixedpoint.unpack_values(req_pkt.payload)
    print(f"Input values ({len(x)}): {x}")

    # Also interpret payload as unsigned (for signedness debugging)
    unsigned_ints = fixedpoint.unpack_ints(req_pkt.payload, signed=False)
    x_unsigned = [v / (1 << 10) for v in unsigned_ints]
    print(f"Input values unsigned ({len(x_unsigned)}): {x_unsigned}")

    # Byte-swap per 16-bit word, then reinterpret as signed fixed-point
    swapped_ints = []
    for v in fixedpoint.unpack_ints(req_pkt.payload, signed=False):
        lo = v & 0xFF
        hi = (v >> 8) & 0xFF
        swapped = (lo << 8) | hi
        if swapped & 0x8000:
            swapped = swapped - 0x10000
        swapped_ints.append(swapped)
    x_swapped = [v / (1 << 10) for v in swapped_ints]

    x_rev = list(reversed(x))
    x_rev_swapped = list(reversed(x_swapped))

    import yaml

    hls_cfg = yaml.safe_load(Path(args.hls_config).read_text())
    cfg = {"model": hls_cfg["model"]}
    model = _build_pytorch_model(cfg)

    import torch
    with torch.no_grad():
        y_pt = model(torch.tensor(x).float().unsqueeze(0)).numpy().squeeze()
    print(f"PyTorch y: {float(y_pt)}")

    try:
        import hls4ml  # type: ignore
    except Exception as exc:
        raise RuntimeError("hls4ml is required to compare hls4ml prediction") from exc

    h = hls_cfg["hls4ml"]
    hls_config = hls4ml.utils.config_from_pytorch_model(
        model,
        input_shape=(len(x),),
        granularity="model",
        backend=h.get("backend", "Vitis"),
        default_reuse_factor=int(h.get("reuse_factor", 1)),
        default_precision=h.get("precision", "ap_fixed<16,6>"),
    )
    hls_model = hls4ml.converters.convert_from_pytorch_model(
        model,
        hls_config=hls_config,
        output_dir=str(Path("sim/fixtures/hls4ml_tmp").resolve()),
        part=h.get("part", "xc7a200tsbg484-1"),
        clock_period=float(h.get("clock_period", 10.0)),
        io_type=h.get("io_type", "io_stream"),
    )
    hls_model.compile()
    y_hls = hls_model.predict(np.ascontiguousarray(np.array(x, dtype=np.float32).reshape(1, -1))).squeeze()
    print(f"hls4ml y: {float(y_hls)}")

    y_hls_unsigned = hls_model.predict(
        np.ascontiguousarray(np.array(x_unsigned, dtype=np.float32).reshape(1, -1))
    ).squeeze()
    print(f"hls4ml y (unsigned input): {float(y_hls_unsigned)}")

    y_hls_rev = hls_model.predict(
        np.ascontiguousarray(np.array(x_rev, dtype=np.float32).reshape(1, -1))
    ).squeeze()
    print(f"hls4ml y (reversed): {float(y_hls_rev)}")

    y_hls_swap = hls_model.predict(
        np.ascontiguousarray(np.array(x_swapped, dtype=np.float32).reshape(1, -1))
    ).squeeze()
    print(f"hls4ml y (byte-swapped): {float(y_hls_swap)}")

    y_hls_rev_swap = hls_model.predict(
        np.ascontiguousarray(np.array(x_rev_swapped, dtype=np.float32).reshape(1, -1))
    ).squeeze()
    print(f"hls4ml y (reversed+swap): {float(y_hls_rev_swap)}")

    pt_payload = fixedpoint.pack_values([float(y_pt)])
    hls_payload = fixedpoint.pack_values([float(y_hls)])
    print(f"PyTorch payload bytes: {_pretty_bytes(pt_payload)}")
    print(f"hls4ml payload bytes : {_pretty_bytes(hls_payload)}")
    print(f"hls4ml payload bytes (reversed): {_pretty_bytes(fixedpoint.pack_values([float(y_hls_rev)]))}")
    print(f"hls4ml payload bytes (byte-swapped): {_pretty_bytes(fixedpoint.pack_values([float(y_hls_swap)]))}")
    print(f"hls4ml payload bytes (reversed+swap): {_pretty_bytes(fixedpoint.pack_values([float(y_hls_rev_swap)]))}")

    if args.expect:
        exp = _read_hex_bytes(Path(args.expect))
        print(f"Expected bytes       : {_pretty_bytes(exp[6:8])}")
    if args.actual:
        act = _read_hex_bytes(Path(args.actual))
        print(f"Actual bytes         : {_pretty_bytes(act[6:8])}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
