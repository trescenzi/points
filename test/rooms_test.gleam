import gleeunit
import rooms
import gleam/erlang/process
import gleam/dict
import gleam/string
import gleam/time/timestamp
import gleam/list

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn create_room_test() {
  let assert Ok(r) = rooms.start()
  let assert Ok(room_name) = process.call(r.data, 10, rooms.CreateRoom)
  assert string.length(room_name) > 0
}

pub fn vote_test() {
  let assert Ok(r) = rooms.start()
  let assert Ok(room_name) = process.call(r.data, 10, rooms.CreateRoom)
  let assert Ok(_votes) = process.call(r.data, 10, rooms.JoinRoom(_, room_name, "user1"))
  let assert Ok(votes) = process.call(r.data, 10, rooms.Vote(_, room_name, "user1", 1))
  let assert Ok(user_vote) = dict.get(votes, "user1")
  assert user_vote == 1
}

pub fn drop_stale_users_test() {
  let now = timestamp.to_unix_seconds(timestamp.system_time())
  let users = [
    #("user1IsNotTooOld", now),
    #("user2IsNotTooOld", now -. 30.0),
    #("user3IsJustTooOld", now -. 120.0),
    #("user4IsWayTooOld", now -. 1200.0),
  ]
  let state = rooms.State(dict.new(), dict.from_list(users))
  let stale_users = rooms.check_for_stale_users(state)
  assert list.length(stale_users) == 2
  let assert Ok(first) = list.first(stale_users) 
  assert first == "user3IsJustTooOld"
  let assert Ok(last) = list.last(stale_users) 
  last == "user4IsWayTooOld"
}
