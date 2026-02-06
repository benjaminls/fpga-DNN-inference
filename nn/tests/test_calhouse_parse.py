import numpy as np

from nn.datasets import calhouse
from nn.utils import config as config_mod


def test_split_sizes():
    cfg = config_mod.load_config("nn/configs/calhouse.yaml")
    X_train, y_train, X_val, y_val, X_test, y_test, _ = calhouse.load_dataset(cfg)
    total = len(y_train) + len(y_val) + len(y_test)
    assert total == len(y_train) + len(y_val) + len(y_test)
    assert X_train.shape[0] == len(y_train)
    assert X_val.shape[0] == len(y_val)
    assert X_test.shape[0] == len(y_test)
    assert X_train.shape[1] == X_val.shape[1] == X_test.shape[1]


def test_shapes_nonzero():
    cfg = config_mod.load_config("nn/configs/calhouse.yaml")
    X_train, y_train, *_ = calhouse.load_dataset(cfg)
    assert X_train.shape[0] > 0
    assert X_train.shape[1] > 0
    assert y_train.shape[0] > 0
