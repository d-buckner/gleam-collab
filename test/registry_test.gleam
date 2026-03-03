import gleeunit/should
import registry

pub fn get_or_create_returns_subject_test() {
  let assert Ok(reg) = registry.start()
  let subj = registry.get_or_create(reg, "room-1")
  should.be_ok(Ok(subj))
}

pub fn same_room_id_returns_same_subject_test() {
  let assert Ok(reg) = registry.start()
  let s1 = registry.get_or_create(reg, "room-42")
  let s2 = registry.get_or_create(reg, "room-42")
  should.equal(s1, s2)
}

pub fn different_room_ids_return_different_subjects_test() {
  let assert Ok(reg) = registry.start()
  let s1 = registry.get_or_create(reg, "room-a")
  let s2 = registry.get_or_create(reg, "room-b")
  should.not_equal(s1, s2)
}
