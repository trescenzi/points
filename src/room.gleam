import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/json
import gleam/otp/actor

pub type Message {
  AddUser(reply: process.Subject(Votes), user_id: String)
  DropUser(user_id: String)
  Vote(reply: process.Subject(Votes), user_id: String, vote: Int)
  GetVotes(reply: process.Subject(Votes))
  GetName(reply: process.Subject(String))
}

pub type Votes =
  Dict(String, Int)

pub type RoomState {
  RoomState(name: String, votes: Votes)
}

pub fn votes_to_json(votes: Votes) -> json.Json {
  json.object([#("votes", json.dict(votes, fn(string) { string }, json.int))])
}

pub type Subject =
  process.Subject(Message)

pub fn handle_message(
  state: RoomState,
  message: Message,
) -> actor.Next(RoomState, Message) {
  case message {
    DropUser(user_id:) -> {
      let votes = dict.drop(state.votes, [user_id])
      actor.continue(RoomState(..state, votes:))
    }
    GetName(reply:) -> {
      process.send(reply, state.name)
      actor.continue(state)
    }
    GetVotes(reply:) -> {
      process.send(reply, state.votes)
      actor.continue(state)
    }
    AddUser(reply:, user_id:) -> {
      let votes = dict.insert(state.votes, user_id, -1)
      let state = RoomState(..state, votes:)
      process.send(reply, state.votes)
      actor.continue(state)
    }
    Vote(reply:, user_id:, vote:) -> {
      let votes = dict.insert(state.votes, user_id, vote)
      let state = RoomState(..state, votes:)
      process.send(reply, state.votes)
      actor.continue(state)
    }
  }
}

pub fn create_room(room_name: String) {
  RoomState(room_name, dict.new())
  |> actor.new()
  |> actor.on_message(handle_message)
  |> actor.start()
}
