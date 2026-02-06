import numpy as np

from nn.metrics import regression


def test_metrics():
    y_true = np.array([0.0, 1.0, 2.0], dtype=np.float32)
    y_pred = np.array([0.0, 2.0, 2.0], dtype=np.float32)
    assert regression.mae(y_true, y_pred) == 1.0 / 3.0
    assert regression.rmse(y_true, y_pred) == np.sqrt((0 + 1 + 0) / 3)
    assert regression.r2(y_true, y_pred) < 1.0
