import blah/other
import blah/word
import chip
import gleam/bytes_tree
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import index
import logging
import mist.{type Connection, type ResponseData}

@external(erlang, "logger", "update_primary_config")
fn logger_update_primary_config(config: Dict(Atom, Atom)) -> Result(Nil, any)

pub fn main() {
  logging.configure()
  let _ =
    logger_update_primary_config(
      dict.from_list([#(atom.create("level"), atom.create("debug"))]),
    )

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))

  let assert Ok(registry) = chip.start(chip.Unnamed)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      logging.log(
        logging.Info,
        "Got a request from: " <> string.inspect(mist.get_client_info(req.body)),
      )
      case request.path_segments(req) {
        [] | ["index"] ->
          response.new(200)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string(index.index_page())),
          )
        ["public", ..rest] -> serve_file(rest)
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: create_ws_actor(_, registry.data),
            on_close: fn(_state) {
              // todo broadcast leave
              io.println("goodbye!")
            },
            handler: fn(state: WebsocketState, message, conn) {
              handle_ws_message(state, message, conn, registry.data)
            },
          )

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(9000)
    |> mist.start

  process.sleep_forever()
}

fn handle_ws_message(
  state: WebsocketState,
  message,
  conn,
  connection_registry: chip.Registry(ConnectionMessage, String),
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
      mist.continue(state)
    }
    mist.Text(command) -> {
      let new_state = case decode_message(command) {
        Ok(message) -> {
          case message.command {
            "joinRoom" -> {
              let room_name = message.value
              chip.register(connection_registry, room_name, state.subject)
              let members = chip.members(connection_registry, room_name, 50)
              // inform every member of the newly joined voter
              list.map(members, fn(subject) {
                process.send(subject, Voted(state.vote))
              })
              let _ = mist.send_text_frame(conn, "joinRoom|success")
              state
            }
            "vote" -> {
              let #(room_name, vote) = case string.split(message.value, ":") {
                [room_name, user_id] -> #(room_name, user_id)
                [] -> #("", "")
                [_, ..] -> #("", "")
              }

              let vote = case int.parse(vote) {
                Ok(vote) -> UserVote(vote: Some(vote), user: state.vote.user)
                Error(_) -> state.vote
              }
              broadcast_vote(
                vote,
                room_name,
                connection_registry,
                state.subject,
              )
              let _ = mist.send_text_frame(conn, "vote|success")

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
      let new_votes = case connection_message {
        Voted(new_vote) -> {
          let votes =
            dict.insert(state.votes, new_vote.user, new_vote.vote)
            |> dict.insert(state.vote.user, state.vote.vote)

          let _ =
            mist.send_text_frame(
              conn,
              "votes|" <> json.to_string(votes_to_json(votes)),
            )
          votes
        }
        GetVote(reply) -> {
          process.send(reply, state.vote)
          state.votes
        }
      }
      mist.continue(WebsocketState(..state, votes: new_votes))
    }
    mist.Binary(_) -> {
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

type UserVote {
  UserVote(vote: Option(Int), user: String)
}

type WebsocketState {
  WebsocketState(
    subject: process.Subject(ConnectionMessage),
    vote: UserVote,
    votes: Dict(String, Option(Int)),
  )
}

fn create_ws_actor(
  _conn,
  connection_registry: chip.Registry(ConnectionMessage, String),
) {
  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  chip.register(connection_registry, "default", self)
  // we start with no vote and a uuid; maybe someday the user can have a name
  let uv = UserVote(vote: None, user: other.uuid())

  #(WebsocketState(subject: self, vote: uv, votes: dict.new()), Some(selector))
}

type WSMessage {
  WSMessage(command: String, value: String)
}

type ConnectionMessage {
  GetVote(process.Subject(UserVote))
  Voted(UserVote)
}

fn w_s_message_decoder() -> decode.Decoder(WSMessage) {
  use command <- decode.field("command", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(WSMessage(command:, value:))
}

fn decode_message(message: String) -> Result(WSMessage, json.DecodeError) {
  json.parse(from: message, using: w_s_message_decoder())
}

fn vote_to_int(vote: Option(Int)) -> Int {
  case vote {
    Some(v) -> v
    None -> -1
  }
}

fn broadcast_vote(
  vote: UserVote,
  room_name: String,
  connection_registry: chip.Registry(ConnectionMessage, String),
  current_subject: process.Subject(ConnectionMessage),
) {
  let members = chip.members(connection_registry, room_name, 50)
  list.each(members, fn(subject) {
    case subject == current_subject {
      True -> Nil
      False -> process.send(subject, Voted(vote))
    }
  })
}

pub fn votes_to_json(votes: Dict(String, Option(Int))) -> json.Json {
  let votes = dict.map_values(votes, fn(_user, vote) { vote_to_int(vote) })
  json.object([#("votes", json.dict(votes, fn(string) { string }, json.int))])
}

fn serve_file(
  //_req: Request(Connection),
  path: List(String),
) -> Response(ResponseData) {
  let file_path = "./priv/public/" <> string.join(path, with: "/")
  mist.send_file(file_path, offset: 0, limit: None)
  |> result.map(fn(file) {
    let content_type = guess_content_type(file_path)
    response.new(200)
    |> response.prepend_header("content-type", content_type)
    |> response.set_body(file)
  })
  |> result.lazy_unwrap(fn() {
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))
  })
}

fn guess_content_type(path: String) -> String {
  case list.reverse(string.split(path, ".")) {
    ["js", ..] -> "text/javascript"
    ["css", ..] -> "text/css"
    _ -> "text/plain"
  }
}
