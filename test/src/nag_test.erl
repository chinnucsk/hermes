-module (nag_test).

-include_lib("eunit/include/eunit.hrl").

basic_nag_test_() ->
  [
    ?assert(1 + 1 =:= 2)
  ]