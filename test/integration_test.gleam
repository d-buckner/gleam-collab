import gleam/erlang/process
import gleeunit/should
import registry
import room

pub fn two_client_sync_integration_test() {
  let assert Ok(reg) = registry.start()
  let room_subj = registry.get_or_create(reg, "test-room")

  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(room_subj, subj_a)
  let id_b = room.join(room_subj, subj_b)

  pump(room_subj, subj_a, id_a, subj_b, id_b, 0)
}

fn pump(rm, subj_a, id_a, subj_b, id_b, rounds) {
  should.be_true(rounds < 30)
  let ma = process.receive(subj_a, 100)
  let mb = process.receive(subj_b, 100)
  case ma, mb {
    Error(Nil), Error(Nil) -> Nil
    Ok(bits), _ ->
      case bits {
        <<0x11, payload:bits>> -> {
          room.sync_msg(rm, id_a, payload)
          pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
        }
        _ -> pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
      }
    _, Ok(bits) ->
      case bits {
        <<0x11, payload:bits>> -> {
          room.sync_msg(rm, id_b, payload)
          pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
        }
        _ -> pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
      }
  }
}

pub fn signal_relay_test() {
  let assert Ok(reg) = registry.start()
  let room_subj = registry.get_or_create(reg, "signal-room")

  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(room_subj, subj_a)
  let id_b = room.join(room_subj, subj_b)

  let _ = drain(subj_b, 5)

  let signal_data = <<"offer":utf8>>
  room.signal(room_subj, id_a, id_b, signal_data)

  let assert Ok(frame) = process.receive(subj_b, 500)
  let assert <<0x12, from:bytes-size(16), data:bits>> = frame
  should.equal(from, id_a)
  should.equal(data, signal_data)
}

fn drain(subj, n) {
  case n {
    0 -> Nil
    _ ->
      case process.receive(subj, 100) {
        Ok(_) -> drain(subj, n - 1)
        Error(Nil) -> Nil
      }
  }
}
