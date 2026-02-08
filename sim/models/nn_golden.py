"""Generate golden INFER_REQ/INFER_RSP packets from a trained PyTorch model."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from host.python.nnfpga import fixedpoint, proto
from nn.datasets import calhouse
from nn.models import mlp_regressor
from nn.utils import config as config_mod


def _write_hex_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for b in data:
            f.write(f"{b:02X}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="Training config (dataset/model)")
    ap.add_argument("--checkpoint", required=True, help="Path to model.pt")
    ap.add_argument("--out-dir", default="sim/fixtures", help="Output directory for hex fixtures")
    ap.add_argument("--index", type=int, default=0, help="Test sample index")
    args = ap.parse_args()

    cfg = config_mod.load_config(args.config)
    X_train, y_train, X_val, y_val, X_test, y_test, _, _ = calhouse.load_dataset(cfg)

    model = mlp_regressor.build_mlp(
        input_dim=X_train.shape[1],
        hidden=cfg["model"]["hidden"],
        dropout=cfg["model"]["dropout"],
    )
    import torch

    model.load_state_dict(torch.load(args.checkpoint, map_location="cpu"))
    model.eval()

    idx = int(args.index)
    if idx < 0 or idx >= X_test.shape[0]:
        raise ValueError(f"index out of range: {idx}")

    x_vec = X_test[idx]
    with torch.no_grad():
        y_pred = model(torch.from_numpy(x_vec).float().unsqueeze(0)).numpy().squeeze()

    payload_in = fixedpoint.pack_values(x_vec.tolist())
    payload_out = fixedpoint.pack_values([float(y_pred)])

    req_pkt = proto.pack_packet(proto.INFER_REQ, payload_in, crc=False)
    rsp_pkt = proto.pack_packet(proto.INFER_RSP, payload_out, crc=False)

    out_dir = Path(args.out_dir)
    _write_hex_bytes(out_dir / "nn_in.hex", req_pkt)
    _write_hex_bytes(out_dir / "nn_out.hex", rsp_pkt)
    print(f"Wrote {out_dir}/nn_in.hex and {out_dir}/nn_out.hex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
