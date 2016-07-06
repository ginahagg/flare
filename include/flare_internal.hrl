-include("flare.hrl").

%% macros
-define(APP, flare).
-define(CHILD(Name, Mod, Args), {Name, {Mod, start_link, Args}, permanent, 5000, worker, [Mod]}).
-define(CLIENT, flare_client).
-define(GET_ENV(Key), ?GET_ENV(Key, undefined)).
-define(GET_ENV(Key, Default), application:get_env(?APP, Key, Default)).
-define(LOOKUP(Key, List), ?LOOKUP(Key, List, undefined)).
-define(LOOKUP(Key, List, Default), shackle_utils:lookup(Key, List, Default)).
-define(MATCH_SPEC(Name), [{{Name, '_'}, [], [true]}]).
-define(SOCKET_OPTIONS, [
    binary,
    {packet, 4},
    {send_timeout, 50},
    {send_timeout_close, true}
]).
-define(SUPERVISOR, flare_sup).
-define(TIMEOUT, timer:seconds(5)).

%% defaults
-define(DEFAULT_BOOTSTRAP_BROKERS, [{"127.0.0.1", 9092}]).
-define(DEFAULT_BROKER_BACKLOG_SIZE, 1024).
-define(DEFAULT_BROKER_POOL_SIZE, 1).
-define(DEFAULT_BROKER_POOL_STRATEGY, random).
-define(DEFAULT_BROKER_RECONNECT, true).
-define(DEFAULT_BROKER_RECONNECT_MAX, timer:minutes(2)).
-define(DEFAULT_BROKER_RECONNECT_MIN, timer:seconds(1)).
-define(DEFAULT_TIMEOUT, timer:seconds(1)).
-define(DEFAULT_TOPIC_BUFFER_DELAY_MAX, timer:seconds(1)).
-define(DEFAULT_TOPIC_BUFFER_POOL_SIZE, 2).
-define(DEFAULT_TOPIC_BUFFER_SIZE_MAX, 10000).

%% ETS tables
-define(ETS_TABLE_TOPIC, flare_topic).

%% msgs
-define(MSG_METADATA, metadata).
-define(MSG_TIMEOUT, timeout).