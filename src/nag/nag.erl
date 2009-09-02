%%%-------------------------------------------------------------------
%%% File    : nag.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Mon Aug 10 00:19:48 PDT 2009
%%%-------------------------------------------------------------------

-module (nag).
-include ("hermes.hrl").
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
          sleep_delay      % delay between lags
        }).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
  SleepDelay = case application:get_env(hermes, nag_delay) of
    { ok, D } ->  D;
    undefined -> ?DEFAULT_NAG_DELAY
  end,
  start_nag_timer(SleepDelay),
  {ok, #state{
    sleep_delay = SleepDelay
  }}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({nag, Interval}, #state{sleep_delay = SleepDelay} = State) ->
  {ok, MonReturn} = ambassador:ask("monitors", []),
  Monitors = lists:map(fun(MonString) -> 
    LocalMon = case string:tokens(MonString, ":") of
      [M, "null"] -> M;
      E           -> E
    end,
    utils:turn_to_atom(LocalMon)
  end, MonReturn),
  % ?INFO("Time to nag: ~p~n", [Monitors]),
  lists:map(fun(Mon) ->
    Avg = mon_server:get_average_over(Mon, Interval),
    % ?INFO("Average: ~p for ~p~n", [Avg, Mon]),
    % [{"1250201400",0.4}]
    % Toss out the top 2 values
    [_|SecondMostAverage] = Avg,
    [_|ThirdMostAverage] = SecondMostAverage,
    [LastTuple|_] = ThirdMostAverage,
    
    {_Timestamp, Float} = LastTuple,
    ?TRACE("Asking", [erlang:atom_to_list(Mon), erlang:float_to_list(Float)]),
    Out = ambassador:ask("run_monitor", [
                                          erlang:atom_to_list(Mon),
                                          erlang:float_to_list(Float)
                                        ]),
    
    case Out of
      {ok, [Resp]} ->
        ?TRACE("Resp", [Resp]),
        case string:tokens(Resp, ":") of
          ["vote_for", Action]  -> athens:call_ambassador_election(Mon, Action);
          [Action]              -> ambassador:ask(Action, []);
          Else                  -> ?INFO("Unhandled Event: ~p~n", [Else])
        end,
        % ?INFO("VOTE ACTION!: ~p (Load: ~p)~n", [Resp, Float]),
        timer:sleep(1000),
        Resp;
      {error, _} -> ok
    end
    end, Monitors),
  start_nag_timer(SleepDelay),
  {noreply, State};
  
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

start_nag_timer(SleepDelay) -> timer:send_after(SleepDelay, {nag, 600}).
