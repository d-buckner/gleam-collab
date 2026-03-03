import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import room.{type RoomMsg}

pub type RegistryMsg {
  GetOrCreate(room_id: String, reply_with: Subject(Subject(RoomMsg)))
}

type RegistryState =
  Dict(String, Subject(RoomMsg))

pub fn start() -> Result(Subject(RegistryMsg), actor.StartError) {
  actor.new(dict.new())
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

pub fn get_or_create(
  registry: Subject(RegistryMsg),
  room_id: String,
) -> Subject(RoomMsg) {
  actor.call(registry, waiting: 5000, sending: fn(reply) {
    GetOrCreate(room_id, reply)
  })
}

fn handle_message(
  state: RegistryState,
  msg: RegistryMsg,
) -> actor.Next(RegistryState, RegistryMsg) {
  case msg {
    GetOrCreate(room_id, reply_with) -> {
      case dict.get(state, room_id) {
        Ok(existing_subject) -> {
          process.send(reply_with, existing_subject)
          actor.continue(state)
        }
        Error(Nil) -> {
          let assert Ok(room_subject) = room.start()
          let new_state = dict.insert(state, room_id, room_subject)
          process.send(reply_with, room_subject)
          actor.continue(new_state)
        }
      }
    }
  }
}
