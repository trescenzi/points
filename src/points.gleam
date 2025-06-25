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
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import index
import logging
import mist.{type Connection, type ResponseData}
import room
import rooms

@external(erlang, "logger", "update_primary_config")
fn logger_update_primary_config(config: Dict(Atom, Atom)) -> Result(Nil, any)

pub fn main() {
  logging.configure()
  let _ =
    logger_update_primary_config(
      dict.from_list([#(atom.create("level"), atom.create("debug"))]),
    )

  let assert Ok(room_manager) = rooms.start()
  let selector = process.new_selector()
  let state = room_manager.data

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      logging.log(
        logging.Info,
        "Got a request from: " <> string.inspect(mist.get_client_info(req.body)),
      )
      case request.path_segments(req) {
        [] | ["index"] ->
          response.new(200)
          //          |> response.prepend_header("my-value", "abc")
          //          |> response.prepend_header("my-value", "123")
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string(index.index_page())),
          )
        ["public", ..rest] -> serve_file(rest)
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn(_conn) { #(state, Some(selector)) },
            on_close: fn(_state) { io.println("goodbye!") },
            handler: handle_ws_message,
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

type WSMessage {
  WSMessage(command: String, value: String)
}

fn w_s_message_decoder() -> decode.Decoder(WSMessage) {
  use command <- decode.field("command", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(WSMessage(command:, value:))
}

fn decode_message(message: String) -> Result(WSMessage, json.DecodeError) {
  json.parse(from: message, using: w_s_message_decoder())
}

fn parse_user_and_room(value: String) -> #(String, String) {
  case string.split(value, ":") {
    [room_name, user_id] -> #(room_name, user_id)
    [] -> #("", "")
    [_, ..] -> #("", "")
  }
}

fn handle_ws_message(state, message, conn) {
  case message {
    mist.Text("ping") -> {
      echo "ping"
      let assert Ok(_) = mist.send_text_frame(conn, "pong")
      mist.continue(state)
    }
    mist.Text(command) -> {
      echo "command"
      echo command
      let _ = case decode_message(command) {
        Ok(message) -> {
          case message.command {
            "userPing" -> {
              echo "user pinged: " <> message.value
              mist.send_text_frame(conn, "userPong|" <> message.value)
            }
            "createRoom" -> {
              let assert Ok(_) = case
                process.call(state, 10, rooms.CreateRoom)
              {
                Ok(room_name) ->
                  mist.send_text_frame(conn, "createRoom|" <> room_name)
                Error(_) -> mist.send_text_frame(conn, "createRoom|ERROR")
              }
            }
            "leaveRoom" -> {
              let #(room_name, user_id) = parse_user_and_room(message.value)
              let assert Ok(_) = case
                process.call(state, 10, rooms.JoinRoom(_, room_name, user_id))
              {
                Ok(votes) ->
                  mist.send_text_frame(
                    conn,
                    "joinRoom|" <> json.to_string(room.votes_to_json(votes)),
                  )
                Error(_) ->
                  mist.send_text_frame(
                    conn,
                    "joinRoom|{\"error\": \"not_found\"}",
                  )
              }
            }
            "joinRoom" -> {
              let #(room_name, user_id) = parse_user_and_room(message.value)
              let assert Ok(_) = case
                process.call(state, 10, rooms.JoinRoom(_, room_name, user_id))
              {
                Ok(votes) ->
                  mist.send_text_frame(
                    conn,
                    "joinRoom|" <> json.to_string(room.votes_to_json(votes)),
                  )
                Error(_) ->
                  mist.send_text_frame(
                    conn,
                    "joinRoom|{\"error\": \"not_found\"}",
                  )
              }
            }
            "vote" -> {
              let #(room_name, user_id, vote) = case
                string.split(message.value, ":")
              {
                [room_name, user_id, vote] -> {
                  let vote = case int.parse(vote) {
                    Ok(vote) -> vote
                    Error(_) -> -1
                  }
                  #(room_name, user_id, vote)
                }
                [] -> #("", "", -1)
                [_, ..] -> #("", "", -1)
              }
              let assert Ok(_) = case
                process.call(state, 10, rooms.Vote(_, room_name, user_id, vote))
              {
                Ok(votes) ->
                  mist.send_text_frame(
                    conn,
                    "vote|" <> json.to_string(room.votes_to_json(votes)),
                  )
                Error(_) ->
                  mist.send_text_frame(conn, "vote|{\"error\": \"not_found\"}")
              }
            }
            unknown ->
              mist.send_text_frame(conn, "Error unknown command:" <> unknown)
          }
        }
        Error(_) -> {
          mist.send_text_frame(conn, "Error decoding message:" <> command)
        }
      }

      mist.continue(state)
    }
    mist.Binary(_) | mist.Custom(_) -> {
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn serve_file(
  //_req: Request(Connection),
  path: List(String),
) -> Response(ResponseData) {
  echo "serving file"
  let file_path = "./priv/public/" <> string.join(path, with: "/")
  echo "file path: " <> file_path
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
