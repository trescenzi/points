import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/otp/actor
import room
import blah/word
import gleam/time/timestamp
import gleam/list

fn now() -> Float {
  timestamp.to_unix_seconds(timestamp.system_time())
}

pub type Message {
  CreateRoom(reply: process.Subject(Result(String, Nil))) // Creates a single room, provides the room's name
  UserPing(user_id: String) // user pings to inform that client is still alive
  JoinRoom(
    reply: process.Subject(Result(room.Votes, Nil)), 
    room_name: String,
    user_id: String
  ) // Users can join any number of rooms but only one at a time
  LeaveRoom(
    room_name: String,
    user_id: String
  ) // Users leave specific rooms one at a time
  Vote(
    reply: process.Subject(Result(room.Votes, Nil)),
    room_name: String,
    user_id: String,
    vote: Int
  ) // Users vote to specific rooms
  GetRooms(reply: process.Subject(Rooms)) // Provides rooms if introspection is necessary
}

pub type Rooms = Dict(String, room.Subject) 
pub type UserPings = Dict(String, Float)

pub type State {
  State(rooms: Rooms, pings: UserPings)
}

pub fn start() {
  State(rooms: dict.new(), pings: dict.new())
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn check_for_stale_users(state: State) -> List(String) {
  let current_time = now()
  dict.filter(state.pings, fn (_user_id, last_ping_time) {
    current_time -. last_ping_time >. 120.0
  }) 
  |>  dict.keys
}

pub fn drop_stale_users(state: State) -> Nil {
  let stale_users = check_for_stale_users(state)
  use user <- list.each(stale_users)
  echo "dropping user " <> user <> " from all rooms due to stale pings"
  use _room_id, room <- dict.each(state.rooms)
  process.send(room, room.DropUser(user))
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  drop_stale_users(state)
  case message {
    GetRooms(reply:) -> {
      process.send(reply, state.rooms)
      actor.continue(state)
    }
    UserPing(user_id:) -> {
      actor.continue(State(..state, pings: dict.insert(state.pings, user_id, now())))
    }
    CreateRoom(reply:) -> {
      let room_name = word.noun() <> "_" <> word.verb() <> "_" <> word.adverb()
      let room = room.create_room(room_name)
      case room {
        Ok(room) -> {
          let rooms = dict.insert(state.rooms, room_name, room.data)
          process.send(reply, Ok(room_name))
          actor.continue(State(..state, rooms: rooms))
        }
        Error(_) -> {
          actor.continue(state)
        }
      }
    }
    LeaveRoom(room_name:, user_id:) -> {
      case dict.get(state.rooms,room_name) {
        Ok(room) -> {
          process.send(room, room.DropUser(user_id))
          actor.continue(state)
        }
        Error(_) -> {
          actor.continue(state)
        }
      }
    }
    JoinRoom(reply:, room_name:, user_id:) -> {
      case dict.get(state.rooms,room_name) {
        Ok(room) -> {
          let votes = process.call(room, 10, room.AddUser(_, user_id))
          process.send(reply, Ok(votes))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
      }
    }
    Vote(reply:, room_name:, user_id:, vote:) -> {
      case dict.get(state.rooms,room_name) {
        Ok(room) -> {
          let votes = process.call(room, 10, room.Vote(_, user_id, vote))
          process.send(reply, Ok(votes))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
      }
    }
  }
}
