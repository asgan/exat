%% Author: michal
%% Created: 17-05-2012
%% Description: TODO: Add description to mobile_agent
-module(mobile_agent).

-extends(agent).

-behaviour(agent).

%%
%% Include files
%%

-include("proc_mobility.hrl").

-include("agent.hrl").
%%
%% Exported Functions
%%
-export([new/3, new_with_state/3]).

%% gen_server callbacks
-export([handle_call/3]).

%%
%% API
%%

new(AgentName, Callback, Parameters) ->
    %%io:format("mobile agent cretion ~p ~p ~p ~p", [AgentName, atom_to_list(AgentName), Callback, Parameters]),
    {match, _} = re:run(atom_to_list(AgentName), "@"),
    gen_server:start({local, AgentName},
                     mobile_agent, [AgentName, Callback, Parameters],
                     []).

new_with_state(AgentName, Callback, State) ->
    gen_server:start({local, AgentName},
                     mobile_agent, [AgentName, Callback, State],
                     []).

%% ====================================================================
%% Gen Server
%% ====================================================================

handle_call({mobility, send_me, Destination}, _From,
            #agent_state{name = AgentName, callback = Callback, int_state = IntState} = State) ->
    %%  code:get_object_code(State#agent_state.callback)
    Params = ams:get_migration_parameters(State#agent_state.name, Destination),
    case interprete_params(Params, Destination) of
        {ok, PMSAddr} ->
            State0 = {AgentName, Callback, IntState},
            case proc_mobility:migrate(#mproc_state{name=AgentName, module=Callback, state=State0, code=[]}, PMSAddr) of
                ok ->
                    MyselfPid = self(),
                    spawn(fun() ->
                                  erlang:monitor(process, MyselfPid),
                                  receive
                                      {'DOWN', _, _, MyselfPid, _} -> %%agent died and deregistered
                                          NewPid = proc_mobility:whereis_name(AgentName),
                                          ams:register_agent(AgentName, [Destination], NewPid)
                                  after 3000 ->
                                          io:format("sth went wrong, didn't get DOWN message!")
                                  end
                          end),
                    {stop, normal, ok, State};
                Result ->
                    {reply, Result, State}
            end;
        _ ->
            {reply, {error, "Cannot migrate to given destination"}, State}
    end;

handle_call({mobility, register}, _From, State) ->
    true = proc_mobility:register_name(State#agent_state.name, self()),
    {reply, {ok, self()}, State};


handle_call(Request, From, State) ->
    agent:handle_call(Request, From, State).

%%
%% Local Functions
%%
interprete_params(<<"erl", Node/binary>>, _) -> {ok, binary_to_atom(Node, utf8)};
interprete_params(<<"tcp", Port/binary>>, Dest) ->
    {match, [_, HostP]} = re:run(Dest, "http://([a-zA-Z0-9\.]*):*[-9]*"),
    %%io:format("dest ~p host ~p~n", [Dest, HostP]),
    Host = binary:part(Dest, HostP),
    {ok,{tcp, binary_to_list(Host), list_to_integer(binary_to_list(Port))}};
interprete_params(_, _) -> error.
