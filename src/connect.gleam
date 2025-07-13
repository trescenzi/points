import envoy
import gleam/erlang/atom
import gleam/erlang/node.{type ConnectError, type Node}
import gleam/int
import gleam/list
import gleam/string

pub fn connect_to_other_nodes() -> List(Result(Node, ConnectError)) {
  let ips = discover_host_ips()
  echo "====== FOUND IPS ====="
  echo ips
  echo "========= IPS ========"
  try_connect_ips(ips)
}

/// A DNS error that can occur when discovering nodes.
pub type LookupError {
  FormatError
  QueryFormatError
  ServerFailure
  NoSuchDomain
  Timeout
  NotImplemented
  Refused
  BadVersion
  PosixError(String)
  Unknown
}

@external(erlang, "connect_ffi", "lookup_a")
fn lookup_a(
  hostname: String,
  timeout: Int,
) -> Result(List(#(Int, Int, Int, Int)), LookupError)

@external(erlang, "connect_ffi", "lookup_aaaa")
fn lookup_aaaa(
  hostname: String,
  timeout: Int,
) -> Result(List(#(Int, Int, Int, Int, Int, Int, Int, Int)), LookupError)

pub type IP {
  IPV4(String)
  IPV6(String)
}

fn parse_v4_tuple(ip: #(Int, Int, Int, Int)) -> IP {
  let #(a, b, c, d) = ip

  let astring = int.to_string(a)
  let bstring = int.to_string(b)
  let cstring = int.to_string(c)
  let dstring = int.to_string(d)

  IPV4(string.join([astring, bstring, cstring, dstring], "."))
}

fn parse_v6_part(part: Int) -> String {
  case int.to_base16(part) {
    //"0" -> ""
    // TODO fly's ipv6 strings are lowecase and include 0s. Not sure about a good way to be consistent here
    x -> x |> string.lowercase
  }
}

fn parse_v6_tuple(ip: #(Int, Int, Int, Int, Int, Int, Int, Int)) -> IP {
  let #(a, b, c, d, e, f, g, h) = ip

  let astring = parse_v6_part(a)
  let bstring = parse_v6_part(b)
  let cstring = parse_v6_part(c)
  let dstring = parse_v6_part(d)
  let estring = parse_v6_part(e)
  let fstring = parse_v6_part(f)
  let gstring = parse_v6_part(g)
  let hstring = parse_v6_part(h)

  IPV6(string.join(
    [astring, bstring, cstring, dstring, estring, fstring, gstring, hstring],
    ":",
  ))
}

fn discover_host_ips() -> List(IP) {
  let dns_query = case envoy.get("DNS_CLUSTER_QUERY") {
    Ok(h) -> h
    Error(_) -> ""
  }

  let v4ips = case lookup_a(dns_query, 1000) {
    Ok(ips) -> ips
    Error(_) -> []
  }
  let v6ips = case lookup_aaaa(dns_query, 1000) {
    Ok(ips) -> ips
    Error(_) -> []
  }

  list.flatten([
    list.map(v4ips, parse_v4_tuple),
    list.map(v6ips, parse_v6_tuple),
  ])
}

fn try_connect_ip(basename: String, ip: IP) -> Result(Node, ConnectError) {
  case ip {
    IPV4(ip) -> basename <> "@" <> ip
    IPV6(ip) -> basename <> "@" <> ip
  }
  |> atom.create
  |> node.connect
}

fn try_connect_ips(ips: List(IP)) -> List(Result(Node, ConnectError)) {
  let basename = case envoy.get("ERLANG_BASENAME") {
    Ok(h) -> h
    Error(_) -> ""
  }
  list.map(ips, try_connect_ip(basename, _))
}
