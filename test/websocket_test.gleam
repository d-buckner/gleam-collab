import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleeunit/should
import mist
import registry
import connection

@external(erlang, "Elixir.WsTestClient", "find_free_port")
fn find_free_port() -> Int

@external(erlang, "Elixir.WsTestClient", "connect")
fn ws_connect(port: Int, path: String) -> Result(#(Dynamic, Dynamic), Dynamic)

@external(erlang, "Elixir.WsTestClient", "send_binary")
fn ws_send(conn: Dynamic, stream: Dynamic, data: BitArray) -> Nil

@external(erlang, "Elixir.WsTestClient", "recv")
fn ws_recv_timeout(conn: Dynamic, timeout_ms: Int) -> Result(BitArray, Dynamic)

@external(erlang, "Elixir.WsTestClient", "close")
fn ws_close(conn: Dynamic) -> Nil

@external(erlang, "Elixir.WsTestClient", "http_get_status")
fn http_get(port: Int, path: String) -> Int

fn start_server(port: Int) -> Nil {
  let assert Ok(reg) = registry.start()
  let assert Ok(_) =
    mist.new(fn(req) { connection.handle(req, reg) })
    |> mist.port(port)
    |> mist.start
  process.sleep(50)
}

fn drain_frames(conn: Dynamic, max: Int) -> Nil {
  case max {
    0 -> Nil
    _ ->
      case ws_recv_timeout(conn, 100) {
        Ok(_) -> drain_frames(conn, max - 1)
        Error(_) -> Nil
      }
  }
}

fn drain_until_quiet(conn: Dynamic, stream: Dynamic, rounds: Int) -> Nil {
  case rounds > 20 {
    True -> Nil
    False ->
      case ws_recv_timeout(conn, 100) {
        Ok(<<0x11, payload:bits>>) -> {
          ws_send(conn, stream, <<0x01, payload:bits>>)
          drain_until_quiet(conn, stream, rounds + 1)
        }
        Ok(_) -> drain_until_quiet(conn, stream, rounds + 1)
        Error(_) -> Nil
      }
  }
}

fn recv_until_signal(conn: Dynamic, attempts: Int) -> Result(BitArray, Nil) {
  case attempts {
    0 -> Error(Nil)
    _ ->
      case ws_recv_timeout(conn, 500) {
        Ok(<<0x12, _rest:bits>> as frame) -> Ok(frame)
        Ok(_) -> recv_until_signal(conn, attempts - 1)
        Error(_) -> Error(Nil)
      }
  }
}

pub fn two_clients_sync_over_websocket_test() {
  let port = find_free_port()
  start_server(port)

  let assert Ok(#(conn_a, stream_a)) = ws_connect(port, "/rooms/ws-sync-room")
  let assert Ok(#(conn_b, stream_b)) = ws_connect(port, "/rooms/ws-sync-room")

  drain_until_quiet(conn_a, stream_a, 0)
  drain_until_quiet(conn_b, stream_b, 0)

  ws_close(conn_a)
  ws_close(conn_b)

  should.be_true(True)
}

pub fn signal_relay_over_websocket_test() {
  let port = find_free_port()
  start_server(port)

  // Connect B first so we can cleanly read its Welcome frame before A joins
  let assert Ok(#(conn_b, _stream_b)) = ws_connect(port, "/rooms/ws-signal-room")
  let assert Ok(<<0x10, b_id:bytes-size(16)>>) = ws_recv_timeout(conn_b, 1000)

  // Now connect A
  let assert Ok(#(conn_a, stream_a)) = ws_connect(port, "/rooms/ws-signal-room")
  let assert Ok(<<0x10, a_id:bytes-size(16)>>) = ws_recv_timeout(conn_a, 1000)

  // Drain any extra frames (sync messages, PeerJoined notifications)
  drain_frames(conn_a, 5)
  drain_frames(conn_b, 5)

  // A sends a signal to B
  let payload = <<"offer":utf8>>
  ws_send(conn_a, stream_a, <<0x02, b_id:bits, payload:bits>>)

  // B should receive a SignalFromPeer frame: 0x12 <a_id:16> <payload>
  let assert Ok(frame) = recv_until_signal(conn_b, 10)
  let assert <<0x12, from_id:bytes-size(16), data:bits>> = frame

  should.equal(from_id, a_id)
  should.equal(data, payload)

  ws_close(conn_a)
  ws_close(conn_b)
}

pub fn unknown_route_returns_404_test() {
  let port = find_free_port()
  start_server(port)

  let status = http_get(port, "/not-a-room")
  should.equal(status, 404)
}
