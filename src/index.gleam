import nakai
import nakai/attr
import nakai/html.{type Node}

fn head() -> Node {
  html.Head([
    html.title("Point your tickets!"),
    html.Script([attr.src("/public/main.js")], ""),
    html.Script(
      [
        attr.data("goatcounter", "https://points.goatcounter.com/count"),
        attr.async(),
        attr.src("//gc.zgo.at/count.js"),
      ],
      "",
    ),
    html.link([attr.href("/public/main.css"), attr.rel("stylesheet")]),
  ])
}

fn vote_option(quantity: String) -> Node {
  let data_quantity = attr.data("quantity", quantity)
  html.div([attr.class("vote_option vote_card"), data_quantity], [
    html.div([attr.class("front"), data_quantity], [
      html.div([attr.class("tl"), data_quantity], [html.Text(quantity)]),
      html.div([attr.class("tr"), data_quantity], [html.Text(quantity)]),
      html.div([attr.class("m"), data_quantity], [html.Text(quantity)]),
      html.div([attr.class("bl"), data_quantity], [html.Text(quantity)]),
      html.div([attr.class("br"), data_quantity], [html.Text(quantity)]),
    ]),
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
      html.div([attr.class("buttons")], [
        html.button([attr.id("room_button")], [html.Text("Create Room")]),
        html.button([attr.id("share_button"), attr.class("hidden")], [
          html.Text("Share"),
        ]),
        html.button([attr.id("show_button")], [html.Text("Show Votes")]),
        html.button([attr.id("reset_button")], [html.Text("Reset Votes")]),
        html.label([attr.class("toggle")], [
          html.div([], [html.Text("You are a:")]),
          html.input([
            attr.name("user_type"),
            attr.id("user_type"),
            attr.type_("checkbox"),
          ]),
        ]),
      ]),
      html.div([attr.id("voting_area")], [
        vote_option("0"),
        vote_option("1"),
        vote_option("2"),
        vote_option("3"),
        vote_option("5"),
        vote_option("8"),
        vote_option("13"),
        //vote_option("☕"),
      ]),
      html.div([], [
        html.div([attr.id("vote_area")], []),
        html.div([attr.id("stats")], [
          html.h3_text([], "Stats"),
          html.div([], [
            html.span_text([], "Mean "),
            html.span_text([attr.id("mean")], "--"),
          ]),
          html.div([], [
            html.span_text([], "Mode "),
            html.span_text([attr.id("mode")], "--"),
          ]),
          html.div([], [
            html.span_text([], "Std. "),
            html.span_text([attr.id("std")], "--"),
          ]),
        ]),
      ]),
    ]),
  ])
}

pub fn index_page() {
  nakai.to_string(html.Html([], [head(), body()]))
}
