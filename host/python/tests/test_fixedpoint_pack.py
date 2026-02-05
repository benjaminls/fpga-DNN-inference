from nnfpga import fixedpoint


def test_pack_unpack_roundtrip():
    values = [0.0, 1.0, -1.0, 1.5]
    payload = fixedpoint.pack_values(values, data_width=16, frac_width=8, signed=True)
    ints = fixedpoint.unpack_ints(payload, data_width=16, signed=True)
    assert ints[0] == 0
    assert ints[1] == 256
    assert ints[2] == -256
    assert ints[3] == 384


def test_saturation():
    payload = fixedpoint.pack_values([1000.0], data_width=16, frac_width=8, signed=True)
    ints = fixedpoint.unpack_ints(payload, data_width=16, signed=True)
    assert ints[0] == 32767
