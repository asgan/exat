%%
%% agent.erl
%%
%% ----------------------------------------------------------------------
%%
%%  eXAT, an erlang eXperimental Agent Tool
%%  Copyright (C) 2005-07 Corrado Santoro (csanto@diit.unict.it)
%%
%%  This program is free software: you can redistribute it and/or modify
%%  it under the terms of the GNU General Public License as published by
%%  the Free Software Foundation, either version 3 of the License, or
%%  (at your option) any later version.
%%
%%  This program is distributed in the hope that it will be useful,
%%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%  GNU General Public License for more details.
%%
%%  You should have received a copy of the GNU General Public License
%%  along with this program.  If not, see <http://www.gnu.org/licenses/>

-module(agent).

-behaviour(gen_server).

-include("acl.hrl").

-include("fipa_ontology.hrl").

-include("agent.hrl").

-export([get_acl_semantics/1, get_mind/1, get_property/2, join/1,
         kill/1, start_link/2, start_link/3, set_property/3, set_rational/3,
         stop/1, cast/2, call/2
        ]).

-export([names/1, name/1, host/1, ap/1, full_local_name/1]).

-export([code_change/3, terminate/2, handle_call/3, handle_cast/2,
         init/1, handle_info/2, behaviour_info/1]).

%% send_message/4,
%% get_message/1,
%% match_message/2,

-spec behaviour_info(atom()) -> 'undefined' | [{atom(), arity()}].
behaviour_info(callbacks) ->
    [{init,2},{handle_call,3},{handle_cast,2},{handle_info,2},
     {terminate,2},{code_change,3}];
behaviour_info(_Other) ->
    undefined.


start_link(AgentName, Callback) ->
    start_link(AgentName, Callback, []).

start_link(AgentName, Callback, Parameters) ->
    gen_server:start_link({local, AgentName},
                          agent, [AgentName, Callback, Parameters],
                          []).

call(Ref, Call) ->
    gen_server:call(Ref, Call).
cast(Ref, Call) ->
    gen_server:cast(Ref, Call).

%%
%% MAIN CALLS
%%
join(_Agent) -> erlang:error(notimpl).

set_property(_Agent, _Property, _Value) ->
    erlang:error(notimpl).

get_property(_Agent, _Property) ->
    erlang:error(notimpl).

set_rational(_Pid, _EngineName, _SemanticsClass) ->
    erlang:error(notimpl).

get_mind(_Pid) -> erlang:error(notimpl).

get_acl_semantics(_Pid) -> erlang:error(notimpl).

stop(Agent) ->
    gen_server:cast(Agent, '$agent_stop').

kill(Agent) -> stop(Agent).

%%
%% CALLBACKS
%%

%%
%% Initialize
%%
init(Args) ->
    [AgentName, Callback, Params0 | _] = Args,
    {NoRegister, Params} = proplists_extract(no_register, Params0, false),
    Registered = 
        case NoRegister of
            false ->
                ams:register_agent(AgentName),
                true;
            _ -> 
                false
        end,
    {ok, IntState} = Callback:init(AgentName, Params),
    {ok, #agent_state{name = AgentName, callback = Callback,
                      int_state = IntState, registered = Registered}}.

%%
%% Terminate
%%
terminate(Reason,
          #agent_state{callback = Callback, name = AgentName,
                       int_state = IntState, registered = Registered} =
              _State) ->
    case Registered of
        true ->
            ams:de_register_agent(AgentName);
        _ -> ok
    end,
    ok = Callback:terminate(Reason, IntState),
    ok.

%%
%% Gets a property from agent
%%
handle_call({get_property, _PropertyName}, _From,
            #agent_state{} = State) ->
    {reply, {error, notimpl}, State};
%%
%% Sets a property
%%
handle_call({set_property, _PropertyName,
             _PropertyValue},
            _From, #agent_state{} = State) ->
    {reply, {error, notimpl}, State};
%%
%% Receives an ACL message in String format
%%
handle_call([acl, AclStr], _From,
            #agent_state{int_state = IntState, callback = Callback} =
                State) ->
    %%io:format("[Agent] Received ACL=~s\n", [Acl]),
    case catch acl:parse_message(AclStr) of
        {'EXIT', _Reason} -> {reply, ok, State};
        Acl ->
            {noreply, IntState2} = Callback:handle_acl(Acl,
                                                       IntState),
            {reply, ok, State#agent_state{int_state = IntState2}}
    end;

%%
%% Receives an ACL message in Erlang format
%%
handle_call([acl_erl_native, Acl], _From,
            #agent_state{int_state = IntState, callback = Callback} =
                State) ->
    {noreply, IntState2} = Callback:handle_acl(Acl,
                                               IntState),
    {reply, ok, State#agent_state{int_state = IntState2}};
handle_call(Call, From,
            #agent_state{int_state = IntState, 
                         callback = Callback} = State) ->
    case Callback:handle_call(Call, From, IntState) of 
        {reply, Reply, IntState2} ->
            {reply, Reply, State#agent_state{int_state=IntState2}};
        {reply, Reply, IntState2, hibernate} ->
            {reply, Reply, State#agent_state{int_state=IntState2}, hibernate};
        {reply, Reply, IntState2, Timeout} ->
            {reply, Reply, State#agent_state{int_state=IntState2}, Timeout};
        {noreply, IntState2} ->
            {noreply, State#agent_state{int_state=IntState2}};
        {noreply, IntState2, hibernate} ->
            {noreply, State#agent_state{int_state=IntState2}, hibernate};
        {noreply, IntState2, Timeout} ->
            {noreply, State#agent_state{int_state=IntState2}, Timeout};
        {stop, Reason, IntState2} ->
            {stop, Reason, State#agent_state{int_state=IntState2}};
        {stop, Reason, Reply, IntState2} ->
            {stop, Reason, Reply, State#agent_state{int_state=IntState2}}
    end.
%%
%% Stops the agent process
%%

handle_cast('$agent_stop', State) ->
    {stop, normal, State};
handle_cast(Cast,
            #agent_state{int_state = IntState, 
                         callback = Callback} = State) ->
    R = Callback:handle_cast(Cast, IntState),
    IntState2 = element(size(R), R),
    setelement(size(R), R,
               State#agent_state{int_state = IntState2}).

handle_info(Info,
            #agent_state{int_state = IntState, 
                         callback = Callback} = State) ->
    case Callback:handle_info(Info, IntState) of
        {noreply, NewIntState} ->
            {noreply, State#agent_state{int_state=NewIntState}};
        {noreply, NewIntState, hibernate} ->
            {noreply, State#agent_state{int_state=NewIntState}, hibernate};
        {noreply, NewIntState, Timeout} ->
            {noreply, State#agent_state{int_state=NewIntState}, Timeout};
        {stop, Reason, NewIntState} ->
            {stop, Reason, State#agent_state{int_state=NewIntState}}
    end.

code_change(OldVsn,
            #agent_state{int_state = IntState, callback = Callback} =
                State,
            Extra) ->
    {ok, IntState2} = Callback:code_change(OldVsn, IntState,
                                           Extra),
    {ok, State#agent_state{int_state = IntState2}}.

proplists_extract(Key, Proplist0, Default) ->
    Params = proplists:unfold(Proplist0),
    case lists:keytake(no_register, 1, Params) of
        {value, {Key, Val}, P} ->
            {Val, P};
        false ->
            {Default, Params}
    end.


%%
%% Utils
%%


names(List) ->
    [ name(A) || A <- List ].

name(#'agent-identifier'{name = N}) ->
    N.

ap(#'agent-identifier'{name = N}) ->
    ap(N);
ap(N) ->
    {Name, HAP} = exat:split_agent_identifier(N),
    HAP.

host(#'agent-identifier'{} = A) ->
    HAP = ap(A),
    host(HAP);
host(HAP) ->
    {_APName, Hostname} = exat:split_exat_platform_identifier(HAP),
    Hostname.

full_local_name(Name) ->
    list_to_atom(Name++"@"++binary_to_list(exat:current_platform())).
