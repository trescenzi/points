import gleam/dict
import gleam/erlang/process
import gleeunit
import room

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn get_name_test() {
  let initial_name = "foo"
  let assert Ok(r) = room.create_room(initial_name)
  let name = process.call(r.data, 10, room.GetName)
  assert name == initial_name
}

pub fn add_user_test() {
  let assert Ok(r) = room.create_room("foo")
  let votes = process.call(r.data, 10, room.AddUser(_, "user1"))
  let assert Ok(user_vote) = dict.get(votes, "user1")
  assert user_vote == -1
}

pub fn drop_user_test() {
  let assert Ok(r) = room.create_room("foo")
  let _votes = process.call(r.data, 10, room.AddUser(_, "user1"))
  process.send(r.data, room.DropUser("user1"))
  let votes = process.call(r.data, 10, room.GetVotes)
  let assert Error(_user_vote) = dict.get(votes, "user1")
}

pub fn vote_test() {
  let assert Ok(r) = room.create_room("foo")
  let votes = process.call(r.data, 10, room.AddUser(_, "user1"))
  let assert Ok(_user_vote) = dict.get(votes, "user1")
  let votes = process.call(r.data, 10, room.Vote(_, "user1", 5))
  let assert Ok(user_vote) = dict.get(votes, "user1")
  assert user_vote == 5
}

pub fn multiple_users_test() {
  let assert Ok(r) = room.create_room("foo")
  process.call(r.data, 10, room.AddUser(_, "user1"))
  process.call(r.data, 10, room.AddUser(_, "user2"))
  process.call(r.data, 10, room.AddUser(_, "user3"))
  let votes = process.call(r.data, 10, room.GetVotes)
  dict.map_values(votes, fn(_user, vote) {
    assert vote == -1
  })

  let votes = process.call(r.data, 10, room.Vote(_, "user1", 1))
  let assert Ok(user_vote) = dict.get(votes, "user1")
  assert user_vote == 1
  let votes = process.call(r.data, 10, room.Vote(_, "user2", 2))
  let assert Ok(user_vote) = dict.get(votes, "user2")
  assert user_vote == 2
  let votes = process.call(r.data, 10, room.Vote(_, "user3", 3))
  let assert Ok(user_vote) = dict.get(votes, "user3")
  assert user_vote == 3
}
