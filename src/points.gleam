import chip
import communication
import connect
import gleam/bytes_tree
import gleam/dict.{type Dict}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/list
import gleam/option.{None}
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

  // We try to connect to other nodes here
  connect.connect_to_other_nodes()
  let assert Ok(node_communicator) =
    communication.start_node_communicator(registry.data)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      logging.log(
        logging.Info,
        "Got a request from: " <> string.inspect(mist.get_client_info(req.body)),
      )
      logging.log(logging.Info, "path: " <> string.inspect(req.path))
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
            on_init: communication.create_ws_actor(_, registry.data),
            on_close: fn(state) {
              communication.broadcast_leave(state.vote.user, registry.data)
              communication.remote_broadcast_leave(
                state.vote.user,
                node_communicator.data,
              )
              io.println("goodbye " <> state.vote.user <> "!")
            },
            handler: fn(state: communication.WebsocketState, message, conn) {
              communication.handle_ws_message(
                state,
                message,
                conn,
                registry.data,
                node_communicator.data,
              )
            },
          )

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(9000)
    |> mist.start

  process.sleep_forever()
}

fn serve_file(
  //_req: Request(Connection),
  path: List(String),
) -> Response(ResponseData) {
  let file_path = "./priv/public/" <> string.join(path, with: "/")
  echo file_path
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
