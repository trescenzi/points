-module(points_ffi).

-ifndef(PRINT).
-define(PRINT(Var), io:format("DEBUG: ~p:~p - ~p~n~n ~p~n~n", [?MODULE, ?LINE, ??Var, Var])).
-endif.

-export([send_to_subject_on_node/3]).

send_to_subject_on_node(Node, Subject, Message) ->
  ?PRINT(Subject),
  case Subject of
    {named_subject, Name} -> erlang:send({Name, Node}, {Name, Message});
    _ -> {error, subject_must_be_named}
  end.
