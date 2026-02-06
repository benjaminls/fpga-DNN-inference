from pathlib import Path

from nn.export import hls4ml_stub


def test_stub_generation(tmp_path: Path):
    out = tmp_path / "hls4ml_config.yaml"
    hls4ml_stub.emit_stub("model.onnx", out)
    text = out.read_text()
    assert "Backend" in text
    assert "Part" in text
