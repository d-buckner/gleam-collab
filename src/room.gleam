import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub type RoomMsg {
  Placeholder
}

type RoomState {
  RoomState
}

pub fn start() -> Result(Subject(RoomMsg), actor.StartError) {
  actor.new(RoomState)
  |> actor.on_message(fn(state, _msg: RoomMsg) { actor.continue(state) })
  |> actor.start
  |> result.map(fn(started) { started.data })
}
