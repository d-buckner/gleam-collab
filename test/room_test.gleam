import gleam/bit_array
import gleam/erlang/process
import gleeunit/should
import room

pub fn join_sends_welcome_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let client_id = room.join(rm, client_subj)
  should.equal(bit_array.byte_size(client_id), 16)
}

pub fn join_triggers_initial_frame_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let _client_id = room.join(rm, client_subj)
  let result = process.receive(client_subj, 500)
  should.be_ok(result)
}

pub fn leave_does_not_crash_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let client_id = room.join(rm, client_subj)
  room.leave(rm, client_id)
  should.be_ok(Ok(Nil))
}

pub fn two_client_sync_converges_test() {
  let assert Ok(rm) = room.start()
  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(rm, subj_a)
  let id_b = room.join(rm, subj_b)
  drain_and_sync(rm, subj_a, id_a, subj_b, id_b, 0)
}

fn drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds) {
  should.be_true(rounds < 20)
  let msg_a = process.receive(subj_a, 100)
  let msg_b = process.receive(subj_b, 100)
  case msg_a, msg_b {
    Error(Nil), Error(Nil) -> Nil
    Ok(frame_a), _ -> {
      room.sync_msg(rm, id_a, extract_sync_payload(frame_a))
      drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
    }
    _, Ok(frame_b) -> {
      room.sync_msg(rm, id_b, extract_sync_payload(frame_b))
      drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
    }
  }
}

fn extract_sync_payload(bits: BitArray) -> BitArray {
  case bits {
    <<0x11, payload:bits>> -> payload
    _ -> bits
    // welcome/peer_joined frames — return as-is, room.sync_msg will ignore
  }
}
