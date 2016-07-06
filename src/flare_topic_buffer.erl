-module(flare_topic_buffer).
-include("flare_internal.hrl").
-include_lib("shackle/include/shackle.hrl").

-compile(inline).
-compile({inline_size, 512}).

-export([
    init/4,
    start_link/3
]).

%% sys behavior
-export([
    system_code_change/4,
    system_continue/3,
    system_get_state/1,
    system_terminate/4
]).

-define(ACK, 1).
-define(COMPRESSION, ?COMPRESSION_SNAPPY).

-record(state, {
    acks             :: 1..65535,
    buffer = []      :: list(),
    buffer_count = 0 :: non_neg_integer(),
    buffer_delay_max :: pos_integer(),
    buffer_size = 0  :: non_neg_integer(),
    buffer_size_max  :: undefined | pos_integer(),
    compression      :: compression(),
    partitions       :: undefined | list(),
    name             :: atom(),
    parent           :: pid(),
    timer_ref        :: undefined | reference(),
    topic            :: topic_name()
}).

-type state() :: #state {}.

%% public
-spec init(pid(), atom(), topic_name(), topic_opts()) ->
    no_return().

init(Parent, Name, Topic, Opts) ->
    process_flag(trap_exit, true),
    register(Name, self()),
    proc_lib:init_ack(Parent, {ok, self()}),

    Name ! ?MSG_METADATA,

    Acks = ?LOOKUP(acks, Opts, ?DEFAULT_TOPIC_ACKS),
    BufferDelayMax = ?LOOKUP(buffer_delay, Opts,
        ?DEFAULT_TOPIC_BUFFER_DELAY),
    BufferSizeMax = ?LOOKUP(buffer_size, Opts,
        ?DEFAULT_TOPIC_BUFFER_SIZE),
    Compression = compression(?LOOKUP(compression, Opts,
        ?DEFAULT_TOPIC_COMPRESSION)),

    loop(#state {
        acks = Acks,
        buffer_delay_max = BufferDelayMax,
        buffer_size_max = BufferSizeMax,
        compression = Compression,
        name = Name,
        parent = Parent,
        timer_ref = timer(BufferDelayMax),
        topic = Topic
    }).

-spec start_link(atom(), topic_name(), topic_opts()) ->
    {ok, pid()}.

start_link(Name, Topic, Opts) ->
    proc_lib:start_link(?MODULE, init, [self(), Name, Topic, Opts]).

%% sys callbacks
-spec system_code_change(state(), module(), undefined | term(), term()) ->
    {ok, state()}.

system_code_change(State, _Module, _OldVsn, _Extra) ->
    {ok, State}.

-spec system_continue(pid(), [], state()) ->
    ok.

system_continue(_Parent, _Debug, State) ->
    loop(State).

-spec system_get_state(state()) ->
    {ok, state()}.

system_get_state(State) ->
    {ok, State}.

-spec system_terminate(term(), pid(), [], state()) ->
    none().

system_terminate(Reason, _Parent, _Debug, _State) ->
    exit(Reason).

%% private
compress(?COMPRESSION_NONE, Messages) ->
    Messages;
compress(?COMPRESSION_SNAPPY, Messages) ->
    {ok, Messages2} = snappy:compress(Messages),
    Messages2.

compression(none) ->
    ?COMPRESSION_NONE;
compression(snappy) ->
    ?COMPRESSION_SNAPPY.

handle_msg(?MSG_METADATA, #state {
        topic = Topic
    } = State) ->

    case flare_metadata:partitions(Topic) of
        {ok, Partitions} ->
            flare_broker_pool:start(Partitions),

            {ok, State#state {
                partitions = Partitions
            }};
        {error, Reason} ->
            % TODO: retry or terminate or move upstream?
            shackle_utils:warning_msg(?CLIENT,
                "metadata error: ~p~n", [Reason]),
            {ok, State}
    end;
handle_msg(?MSG_TIMEOUT, #state {
        buffer = Buffer,
        buffer_delay_max = BufferDelayMax
    } = State) ->

    produce(Buffer, State),

    {ok, State#state {
        buffer = [],
        buffer_count = 0,
        buffer_size = 0,
        timer_ref = timer(BufferDelayMax)
    }};
handle_msg({produce, Message}, #state {
        buffer = Buffer,
        buffer_count = BufferCount,
        buffer_size = BufferSize,
        buffer_size_max = SizeMax
    } = State) ->

    Buffer2 = [Message | Buffer],
    case BufferSize + iolist_size(Message) of
        X  when X > SizeMax ->
            produce(Buffer2, State),

            {ok, State#state {
                buffer = [],
                buffer_count = 0,
                buffer_size = 0
            }};
        X ->
            {ok, State#state {
                buffer = Buffer2,
                buffer_count = BufferCount + 1,
                buffer_size = X
            }}
    end;
handle_msg(#cast {client = ?CLIENT}, State) ->
    {ok, State}.

loop(#state {parent = Parent} = State) ->
    receive
        {'EXIT', _Pid, shutdown} ->
            terminate(State);
        {system, From, Request} ->
            sys:handle_system_msg(Request, From, Parent, ?MODULE, [], State);
        Message ->
            {ok, State2} = handle_msg(Message, State),
            loop(State2)
    end.

produce([], _State) ->
    ok;
produce(_Messages, #state {partitions = undefined}) ->
    ok;
produce(Messages, #state {
        compression = Compression,
        partitions = Partitions,
        topic = Topic
    }) ->

    Messages2 = flare_protocol:encode_message_set(lists:reverse(Messages)),
    Messages3 = compress(Compression, Messages2),
    {Partition, PoolName, _} = shackle_utils:random_element(Partitions),
    Cast = {produce, Topic, Partition, Messages3, ?ACK, ?COMPRESSION},
    shackle:cast(PoolName, Cast).

terminate(#state {
        buffer = Buffer,
        timer_ref = TimerRef
    } = State) ->

    erlang:cancel_timer(TimerRef),
    produce(Buffer, State),
    exit(shutdown).

timer(Time) ->
    erlang:send_after(Time, self(), ?MSG_TIMEOUT).
