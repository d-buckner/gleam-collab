import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/option.{Some}
import mist
import protocol
import registry.{type RegistryMsg}
import room.{type RoomMsg}

pub type ConnState {
  ConnState(room_subj: process.Subject(RoomMsg), client_id: BitArray)
}

/// Main entry point: routes GET /rooms/:room_id to a WebSocket upgrade.
/// All other paths return 404.
pub fn handle(
  req: request.Request(mist.Connection),
  registry_subj: process.Subject(RegistryMsg),
) -> response.Response(mist.ResponseData) {
  case req.method, request.path_segments(req) {
    http.Get, ["rooms", room_id] ->
      upgrade(req, room_id, registry_subj)
    _, _ ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

fn upgrade(
  req: request.Request(mist.Connection),
  room_id: String,
  registry_subj: process.Subject(RegistryMsg),
) -> response.Response(mist.ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) {
      // Create a subject that the room can send frames to this client
      let client_subj = process.new_subject()

      // Get or create the room actor
      let room_subj = registry.get_or_create(registry_subj, room_id)

      // Join the room; receive back our assigned client_id
      let client_id = room.join(room_subj, client_subj)

      // Build a selector so that messages sent to client_subj arrive as
      // Custom(bits) in the WebSocket handler (which runs in the WS process)
      let selector =
        process.new_selector()
        |> process.select(client_subj)

      #(ConnState(room_subj: room_subj, client_id: client_id), Some(selector))
    },
    handler: fn(state: ConnState, msg, conn) {
      case msg {
        mist.Binary(bits) -> {
          case protocol.decode_client(bits) {
            Ok(protocol.SyncMsg(payload)) -> {
              room.sync_msg(state.room_subj, state.client_id, payload)
              mist.continue(state)
            }
            Ok(protocol.Signal(to, data)) -> {
              room.signal(state.room_subj, state.client_id, to, data)
              mist.continue(state)
            }
            Error(_) -> mist.continue(state)
          }
        }
        mist.Custom(bits) -> {
          let _ = mist.send_binary_frame(conn, bits)
          mist.continue(state)
        }
        mist.Closed | mist.Shutdown -> mist.stop()
        mist.Text(_) -> mist.continue(state)
      }
    },
    on_close: fn(state: ConnState) {
      room.leave(state.room_subj, state.client_id)
    },
  )
}
