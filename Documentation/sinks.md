---
title: Sinks
description: Choose where the Elixir client's projections and reducers store read models, and run clients with different sinks.
---

See [Sinks](/chronicle/sinks/) for what a sink is and the storage backends Chronicle ships with. This page covers Elixir-specific configuration: setting the default sink per client, running multiple clients with different sinks, and the `Chronicle.Sinks.WellKnownSinkTypes` reference.

## Default sink

Unless configured otherwise, Chronicle writes read models into MongoDB.
You do not need to set anything — the default is correct for most applications.

## Changing the default sink

Pass `:default_sink_type_id` when starting `Chronicle.Client`:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
  event_store: "my-store",
  default_sink_type_id: :sql,
  read_models: [MyApp.ReadModels.Account],
  reducers: [MyApp.Reducers.AccountReducer]}
```

The option accepts an atom from `Chronicle.Sinks.WellKnownSinkTypes` or a raw
string identifier for custom sink types. The kernel must be configured with the sink you choose; `:sql` needs a kernel with SQL read model storage, as described in the shared [Sinks](/chronicle/sinks/) page.

| Atom | String | Storage backend |
|---|---|---|
| `:mongodb` | `"MongoDB"` | MongoDB (default) |
| `:sql` | `"SQL"` | SQL database |
| `:in_memory` | `"InMemory"` | In-process memory only |
| `:none` | `"None"` | No sink: the read model is not persisted |

The configured sink applies to the projections and reducers that client registers, with one exception: a read model declared with `passive: true` is registered with the `None` sink, because it is computed on demand rather than stored. There is no other per-read-model sink override. An unknown atom raises `ArgumentError` when the client starts.

## Multiple clients with different sinks

If your application needs some read models in MongoDB and others in SQL, start
two separate `Chronicle.Client` instances with different names and assign the
relevant read models to each. `connection_string` here stands for your connection string:

```elixir
children = [
  Supervisor.child_spec(
    {Chronicle.Client,
     name: :mongo_client,
     connection_string: connection_string,
     event_store: "store",
     discover: false,
     default_sink_type_id: :mongodb,
     read_models: [MyApp.ReadModels.AccountSummary]},
    id: :mongo_client
  ),
  Supervisor.child_spec(
    {Chronicle.Client,
     name: :sql_client,
     connection_string: connection_string,
     event_store: "store",
     discover: false,
     default_sink_type_id: :sql,
     read_models: [MyApp.ReadModels.AccountReport]},
    id: :sql_client
  )
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Each client needs its own child id through `Supervisor.child_spec/2`: every `Chronicle.Client` child spec defaults to the id `Chronicle.Client`, and a supervisor refuses two children with the same id. `discover: false` keeps each client from also discovering, and registering, the other client's read models; list each client's event types, reducers and other artifacts explicitly instead.

Pass `:client` when querying to target the right instance:

```elixir
{:ok, summary} = Chronicle.ReadModels.get(MyApp.ReadModels.AccountSummary, id, client: :mongo_client)
{:ok, report} = Chronicle.ReadModels.get(MyApp.ReadModels.AccountReport, id, client: :sql_client)
```

## Reference — `Chronicle.Sinks.WellKnownSinkTypes`

| Function | Returns |
|---|---|
| `WellKnownSinkTypes.mongodb/0` | `"MongoDB"` |
| `WellKnownSinkTypes.sql/0` | `"SQL"` |
| `WellKnownSinkTypes.in_memory/0` | `"InMemory"` |
| `WellKnownSinkTypes.none/0` | `"None"` |
| `WellKnownSinkTypes.resolve/1` | Resolves an atom or passthrough string |

`resolve/1` is used internally by `Chronicle.Client` to normalize the
`:default_sink_type_id` option. You rarely need to call it directly, but it is
useful when building custom tooling or test helpers:

```elixir
alias Chronicle.Sinks.WellKnownSinkTypes

WellKnownSinkTypes.resolve(:mongodb)    # => "MongoDB"
WellKnownSinkTypes.resolve(:sql)        # => "SQL"
WellKnownSinkTypes.resolve("Custom")    # => "Custom"
```
