import gleeunit/should
import protocol

pub fn encode_welcome_test() {
  let id = <<1:size(128)>>
  protocol.encode_server(protocol.Welcome(id))
  |> should.equal(<<0x10, 1:size(128)>>)
}

pub fn encode_sync_to_client_test() {
  let payload = <<1, 2, 3>>
  protocol.encode_server(protocol.SyncToClient(payload))
  |> should.equal(<<0x11, 1, 2, 3>>)
}

pub fn encode_signal_from_peer_test() {
  let from = <<2:size(128)>>
  let data = <<9, 8, 7>>
  protocol.encode_server(protocol.SignalFromPeer(from, data))
  |> should.equal(<<0x12, 2:size(128), 9, 8, 7>>)
}

pub fn encode_peer_joined_test() {
  let id = <<3:size(128)>>
  protocol.encode_server(protocol.PeerJoined(id))
  |> should.equal(<<0x13, 3:size(128)>>)
}

pub fn encode_peer_left_test() {
  let id = <<4:size(128)>>
  protocol.encode_server(protocol.PeerLeft(id))
  |> should.equal(<<0x14, 4:size(128)>>)
}

pub fn decode_sync_msg_test() {
  let payload = <<1, 2, 3>>
  protocol.decode_client(<<0x01, 1, 2, 3>>)
  |> should.be_ok
  |> should.equal(protocol.SyncMsg(payload))
}

pub fn decode_signal_test() {
  let to = <<5:size(128)>>
  let data = <<6, 7>>
  protocol.decode_client(<<0x02, 5:size(128), 6, 7>>)
  |> should.be_ok
  |> should.equal(protocol.Signal(to, data))
}

pub fn decode_unknown_tag_returns_error_test() {
  protocol.decode_client(<<0xFF, 1, 2, 3>>)
  |> should.be_error
}

pub fn decode_truncated_signal_returns_error_test() {
  // Signal needs at least 17 bytes (tag + 16 byte ID)
  protocol.decode_client(<<0x02, 1, 2>>)
  |> should.be_error
}
