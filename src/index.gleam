import nakai
import nakai/attr
import nakai/html.{type Node}

fn head() -> Node {
  html.Head([
    html.title("Point your tickets!"),
    html.Script([attr.src("/public/main.js")], ""),
    html.link([attr.href("/public/main.css"), attr.rel("stylesheet")]),
  ])
}

fn vote_option(quantity: String) -> Node {
  html.div([attr.class("vote_option"), attr.data("quantity", quantity)], [
    html.Text(quantity),
  ])
}

fn body() -> Node {
  html.Body([], [
    html.header([], [
      html.h1_text([], "Points"),
      html.h2([], [
        html.span_text([], "Room: "),
        html.span_text([attr.id("room_name")], "<>"),
      ]),
    ]),
    html.main([], [
      html.button([attr.id("room_button")], [html.Text("Create Room")]),
      html.button([attr.id("share_button"), attr.class("hidden")], [
        html.Text("Share"),
      ]),
      html.div([attr.id("voting_area")], [
        vote_option("0"),
        vote_option("1"),
        vote_option("2"),
        vote_option("3"),
        vote_option("5"),
        vote_option("8"),
        vote_option("13"),
      ]),
      html.div([attr.id("vote_area")], []),
    ]),
  ])
}

pub fn index_page() {
  nakai.to_string(html.Html([], [head(), body()]))
}
