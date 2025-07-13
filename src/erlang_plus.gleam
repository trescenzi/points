import gleam/erlang/node.{type Node}
import gleam/erlang/process.{type Name, type Subject}

@external(erlang, "erlang", "binary_to_atom")
pub fn new_exact_name(name: String) -> Name(message)

@external(erlang, "points_ffi", "send_to_subject_on_node")
pub fn send_to_subject_on_node(
  node: Node,
  subject: Subject(message),
  m: message,
) -> Result(Nil, SendError)

pub type SendError {
  SubjectMustBeNamed
  Noconnect
  Nosuspend
}
