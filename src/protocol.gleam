pub type ServerFrame {
  Welcome(client_id: BitArray)
  SyncToClient(payload: BitArray)
  SignalFromPeer(from: BitArray, data: BitArray)
  PeerJoined(peer_id: BitArray)
  PeerLeft(peer_id: BitArray)
}

pub type ClientFrame {
  SyncMsg(payload: BitArray)
  Signal(to: BitArray, data: BitArray)
}

pub fn encode_server(frame: ServerFrame) -> BitArray {
  case frame {
    Welcome(id) -> <<0x10, id:bits>>
    SyncToClient(payload) -> <<0x11, payload:bits>>
    SignalFromPeer(from, data) -> <<0x12, from:bits, data:bits>>
    PeerJoined(id) -> <<0x13, id:bits>>
    PeerLeft(id) -> <<0x14, id:bits>>
  }
}

pub fn decode_client(bits: BitArray) -> Result(ClientFrame, String) {
  case bits {
    <<0x01, payload:bits>> -> Ok(SyncMsg(payload))
    <<0x02, to:bytes-size(16), data:bits>> -> Ok(Signal(to, data))
    <<0x02, _rest:bits>> -> Error("signal frame too short")
    _ -> Error("unknown frame tag")
  }
}
