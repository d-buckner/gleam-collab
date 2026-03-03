import automerge
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import protocol

pub type RoomMsg {
  Join(client_subj: Subject(BitArray), reply_with: Subject(BitArray))
  Leave(client_id: BitArray)
  SyncFromClient(client_id: BitArray, payload: BitArray)
  SignalMsg(from_id: BitArray, to_id: BitArray, data: BitArray)
}

type Peer {
  Peer(sync_state: automerge.SyncStateRef, subject: Subject(BitArray))
}

type RoomState {
  RoomState(doc: automerge.DocRef, peers: Dict(BitArray, Peer))
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(n: Int) -> BitArray

fn new_client_id() -> BitArray {
  strong_rand_bytes(16)
}

pub fn start() -> Result(Subject(RoomMsg), actor.StartError) {
  let initial = RoomState(doc: automerge.new_doc(), peers: dict.new())
  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

pub fn join(room: Subject(RoomMsg), client_subj: Subject(BitArray)) -> BitArray {
  actor.call(room, waiting: 5000, sending: fn(reply) { Join(client_subj, reply) })
}

pub fn leave(room: Subject(RoomMsg), client_id: BitArray) -> Nil {
  process.send(room, Leave(client_id))
}

pub fn sync_msg(
  room: Subject(RoomMsg),
  client_id: BitArray,
  payload: BitArray,
) -> Nil {
  process.send(room, SyncFromClient(client_id, payload))
}

pub fn signal(
  room: Subject(RoomMsg),
  from_id: BitArray,
  to_id: BitArray,
  data: BitArray,
) -> Nil {
  process.send(room, SignalMsg(from_id, to_id, data))
}

fn send_sync_to_peer(doc: automerge.DocRef, peer: Peer) -> Nil {
  case automerge.generate_sync_message(doc, peer.sync_state) {
    None -> Nil
    Some(payload) -> {
      let frame = protocol.encode_server(protocol.SyncToClient(payload))
      process.send(peer.subject, frame)
    }
  }
}

fn handle_message(
  state: RoomState,
  msg: RoomMsg,
) -> actor.Next(RoomState, RoomMsg) {
  case msg {
    Join(client_subj, reply_with) -> {
      let client_id = new_client_id()
      let sync_state = automerge.new_sync_state()
      let peer = Peer(sync_state: sync_state, subject: client_subj)

      // Notify existing peers that a new client has joined
      let _ =
        dict.each(state.peers, fn(_id, existing_peer) {
          let frame = protocol.encode_server(protocol.PeerJoined(client_id))
          process.send(existing_peer.subject, frame)
        })

      // Add the new peer to the map
      let new_peers = dict.insert(state.peers, client_id, peer)
      let new_state = RoomState(..state, peers: new_peers)

      // Send Welcome frame to the new client
      let welcome = protocol.encode_server(protocol.Welcome(client_id))
      process.send(client_subj, welcome)

      // Send initial sync message to the new client if automerge has one
      send_sync_to_peer(state.doc, peer)

      // Reply to the caller with the assigned client_id
      process.send(reply_with, client_id)

      actor.continue(new_state)
    }

    Leave(client_id) -> {
      let new_peers = dict.delete(state.peers, client_id)
      // Notify remaining peers that this client left
      let _ =
        dict.each(new_peers, fn(_id, peer) {
          let frame = protocol.encode_server(protocol.PeerLeft(client_id))
          process.send(peer.subject, frame)
        })
      actor.continue(RoomState(..state, peers: new_peers))
    }

    SyncFromClient(client_id, payload) -> {
      case dict.get(state.peers, client_id) {
        Error(Nil) -> actor.continue(state)
        Ok(peer) -> {
          case automerge.receive_sync_message(state.doc, peer.sync_state, payload) {
            Error(_) ->
              // Ignore invalid/non-sync payloads (e.g. non-sync frames passed through)
              actor.continue(state)
            Ok(_) -> {
              // Fan out sync messages to all peers
              let _ =
                dict.each(state.peers, fn(_id, p) {
                  send_sync_to_peer(state.doc, p)
                })
              actor.continue(state)
            }
          }
        }
      }
    }

    SignalMsg(from_id, to_id, data) -> {
      case dict.get(state.peers, to_id) {
        Error(Nil) -> actor.continue(state)
        Ok(peer) -> {
          let frame =
            protocol.encode_server(protocol.SignalFromPeer(from_id, data))
          process.send(peer.subject, frame)
          actor.continue(state)
        }
      }
    }
  }
}
