from nnfpga import proto


def test_roundtrip_no_crc():
    payload = bytes([0x01, 0x02, 0x03])
    data = proto.pack_packet(proto.INFER_REQ, payload, crc=False)
    pkt = proto.unpack_packet(data, crc=False)
    assert pkt.pkt_type == proto.INFER_REQ
    assert pkt.payload == payload


def test_bad_magic():
    payload = bytes([0x00])
    data = proto.pack_packet(proto.INFER_REQ, payload, crc=False)
    data = b"\x00\x00" + data[2:]
    try:
        proto.unpack_packet(data, crc=False)
        assert False, "expected bad magic"
    except ValueError:
        pass
