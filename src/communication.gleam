import blah/other
import blah/word
import chip
import connect
import erlang_plus
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/node
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import mist

pub fn handle_ws_message(
  state: WebsocketState,
  message,
  conn,
  connection_registry: chip.Registry(ConnectionMessage, String),
  node_communicator: Subject(RemoteMessage),
) {
  case message {
    mist.Text("ping") -> {
      echo "ping"
      let _ = mist.send_text_frame(conn, "pong")
      mist.continue(state)
    }
    mist.Text("createRoom") -> {
      let room_name = word.noun() <> "_" <> word.verb() <> "_" <> word.adverb()
      chip.register(connection_registry, room_name, state.subject)
      // the ws doesn't care which rooms its in
      // it being a registry is what makes it in a room
      let _ = mist.send_text_frame(conn, "createRoom|" <> room_name)

      // we try to connect again here
      // TODO make this less excessive
      connect.connect_to_other_nodes()

      mist.continue(state)
    }
    mist.Text(command) -> {
      let new_state = case decode_message(command) {
        Ok(message) -> {
          case message.command {
            "joinRoom" -> {
              let room_name = message.value
              chip.register(connection_registry, room_name, state.subject)
              broadcast_join(room_name, connection_registry)
              remote_broadcast_join(room_name, node_communicator)
              let _ = mist.send_text_frame(conn, "joinRoom|success")
              state
            }
            "showVotes" -> {
              let room_name = message.value
              broadcast_show(room_name, connection_registry)
              remote_broadcast_show(room_name, node_communicator)
              state
            }
            "resetVotes" -> {
              let room_name = message.value
              broadcast_reset(room_name, connection_registry)
              remote_broadcast_reset(room_name, node_communicator)
              state
            }
            "vote" -> {
              let #(room_name, vote) = case string.split(message.value, ":") {
                [room_name, user_id] -> #(room_name, user_id)
                [] -> #("", "")
                [_, ..] -> #("", "")
              }

              let vote = case int.parse(vote) {
                Ok(vote) -> UserVote(..state.vote, vote: Some(vote))
                Error(_) -> state.vote
              }
              broadcast_vote(vote, room_name, connection_registry)
              remote_broadcast_vote(vote, room_name, node_communicator)
              let _ = mist.send_text_frame(conn, "vote|success")

              WebsocketState(..state, vote:)
            }
            "setUserType" -> {
              let #(room_name, user_type) = case
                string.split(message.value, ":")
              {
                [room_name, user_id] -> #(room_name, user_id)
                [] -> #("", "")
                [_, ..] -> #("", "")
              }
              let user_type = case user_type {
                "voter" -> Voter
                "spectator" -> Spectator
                _ -> Voter
              }
              let vote = UserVote(..state.vote, user_type:)
              broadcast_user_type_toggle(vote, room_name, connection_registry)
              remote_broadcast_user_type_toggle(
                vote,
                room_name,
                node_communicator,
              )
              WebsocketState(..state, vote:)
            }
            _ -> state
          }
        }
        Error(_) -> state
      }
      mist.continue(new_state)
    }
    mist.Custom(connection_message) -> {
      let state = case connection_message {
        Voted(new_vote) -> {
          let votes =
            dict.insert(state.votes, new_vote.user, new_vote)
            |> dict.insert(state.vote.user, state.vote)

          let _ = communicate_votes(votes, conn)
          WebsocketState(..state, votes:)
        }
        Leave(user) -> {
          let votes =
            state.votes
            |> dict.filter(fn(user_id, _vote) { user != user_id })
          let _ = communicate_votes(votes, conn)
          WebsocketState(..state, votes:)
        }
        Show -> {
          let _ = communicate_votes(state.votes, conn)
          let _ = mist.send_text_frame(conn, "showVotes|now")
          state
        }
        Reset -> {
          let votes =
            dict.map_values(state.votes, fn(_id, vote) {
              UserVote(..vote, vote: None)
            })
          let _ = mist.send_text_frame(conn, "resetVotes|now")
          let _ = communicate_votes(votes, conn)
          WebsocketState(
            ..state,
            votes:,
            vote: UserVote(..state.vote, vote: None),
          )
        }
        Join(room_name) -> {
          // upon a new user joining a room we rebroadcast all votes across the room
          broadcast_vote(state.vote, room_name, connection_registry)
          remote_broadcast_vote(state.vote, room_name, node_communicator)
          state
        }
        ToggleUserType(vote) -> {
          let votes = dict.insert(state.votes, vote.user, vote)
          let _ = communicate_votes(votes, conn)
          WebsocketState(..state, votes:)
        }
      }
      mist.continue(state)
    }
    mist.Binary(_) -> {
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

pub type UserType {
  Voter
  Spectator
}

pub type UserVote {
  UserVote(vote: Option(Int), user: String, user_type: UserType)
}

type Votes =
  Dict(String, UserVote)

pub type WebsocketState {
  WebsocketState(
    subject: process.Subject(ConnectionMessage),
    vote: UserVote,
    votes: Votes,
  )
}

fn user_type_to_json(user_type: UserType) -> json.Json {
  case user_type {
    Voter -> json.string("voter")
    Spectator -> json.string("spectator")
  }
}

fn votes_to_json(votes: Votes) -> json.Json {
  json.dict(votes, fn(string) { string }, user_vote_to_json)
}

fn user_vote_to_json(user_vote: UserVote) -> json.Json {
  let UserVote(vote:, user:, user_type:) = user_vote
  json.object([
    #("vote", case vote {
      None -> json.null()
      Some(value) -> json.int(value)
    }),
    #("user", json.string(user)),
    #("user_type", user_type_to_json(user_type)),
  ])
}

pub fn create_ws_actor(
  conn,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  chip.register(connection_registry, "default", self)
  // we start with no vote and a uuid; maybe someday the user can have a name
  let uv = UserVote(vote: None, user: other.uuid(), user_type: Voter)

  let _ = mist.send_text_frame(conn, "connect|" <> uv.user)

  #(WebsocketState(subject: self, vote: uv, votes: dict.new()), Some(selector))
}

type WSMessage {
  WSMessage(command: String, value: String)
}

pub type ConnectionMessage {
  Voted(UserVote)
  Leave(String)
  Show
  Reset
  Join(String)
  ToggleUserType(UserVote)
}

fn w_s_message_decoder() -> decode.Decoder(WSMessage) {
  use command <- decode.field("command", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(WSMessage(command:, value:))
}

fn decode_message(message: String) -> Result(WSMessage, json.DecodeError) {
  json.parse(from: message, using: w_s_message_decoder())
}

fn broadcast_vote(
  vote: UserVote,
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) { process.send(subject, Voted(vote)) })
}

fn broadcast_join(
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) { process.send(subject, Join(room_name)) })
}

pub fn broadcast_leave(
  user: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, "default", 50)
  list.each(members, fn(subject) { process.send(subject, Leave(user)) })
}

fn broadcast_show(
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) { process.send(subject, Show) })
}

fn broadcast_reset(
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) { process.send(subject, Reset) })
}

fn broadcast_user_type_toggle(
  vote: UserVote,
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) { process.send(subject, ToggleUserType(vote)) })
}

fn remote_broadcast_show(room_name: String, subject: Subject(RemoteMessage)) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteShow(room_name),
  ))
}

fn remote_broadcast_join(room_name: String, subject: Subject(RemoteMessage)) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteJoin(room_name),
  ))
}

fn remote_broadcast_reset(room_name: String, subject: Subject(RemoteMessage)) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteReset(room_name),
  ))
}

pub fn remote_broadcast_leave(user_id: String, subject: Subject(RemoteMessage)) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteLeave(user_id),
  ))
}

fn remote_broadcast_vote(
  vote: UserVote,
  room_name: String,
  subject: Subject(RemoteMessage),
) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteVoted(vote, room_name),
  ))
}

fn remote_broadcast_user_type_toggle(
  vote: UserVote,
  room_name: String,
  subject: Subject(RemoteMessage),
) {
  connect.connect_to_other_nodes()
  echo node.visible()
  list.map(node.visible(), erlang_plus.send_to_subject_on_node(
    _,
    subject,
    RemoteToggleUserType(vote, room_name),
  ))
}

fn communicate_votes(votes: Votes, connection: mist.WebsocketConnection) {
  mist.send_text_frame(
    connection,
    "votes|" <> json.to_string(votes_to_json(votes)),
  )
}

pub fn start_node_communicator(state: chip.Registry(ConnectionMessage, String)) {
  let name = erlang_plus.new_exact_name("node_communicator")
  actor.new(state)
  |> actor.on_message(handle_remote_message)
  |> actor.named(name)
  |> actor.start
}

pub type RemoteMessage {
  RemoteVoted(vote: UserVote, room_name: String)
  RemoteToggleUserType(vote: UserVote, room_name: String)
  RemoteLeave(user_id: String)
  RemoteShow(room_name: String)
  RemoteReset(room_name: String)
  RemoteJoin(room_name: String)
}

fn handle_remote_message(
  state: chip.Registry(ConnectionMessage, String),
  message: RemoteMessage,
) {
  case message {
    RemoteJoin(room_name:) -> broadcast_join(room_name, state)
    RemoteLeave(user_id:) -> broadcast_leave(user_id, state)
    RemoteReset(room_name:) -> broadcast_reset(room_name, state)
    RemoteShow(room_name:) -> broadcast_show(room_name, state)
    RemoteVoted(vote:, room_name:) -> broadcast_vote(vote, room_name, state)
    RemoteToggleUserType(vote:, room_name:) ->
      broadcast_user_type_toggle(vote, room_name, state)
  }
  actor.continue(state)
}
