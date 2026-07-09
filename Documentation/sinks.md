# Sinks

See [Sinks](/chronicle/sinks/) for what a sink is and the storage backends Chronicle ships with. This page covers Elixir-specific configuration: setting the default sink per client, running multiple clients with different sinks, and the `Chronicle.Sinks.WellKnownSinkTypes` reference.

## Default sink

Unless configured otherwise, Chronicle writes read models into MongoDB.
You do not need to set anything — the default is correct for most applications.

## Changing the default sink

Pass `:default_sink_type_id` when starting `Chronicle.Client`:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  default_sink_type_id: :sql,
  read_models: [MyApp.ReadModels.Account],
  reducers: [MyApp.Reducers.AccountReducer]}
```

The option accepts an atom from `Chronicle.Sinks.WellKnownSinkTypes` or a raw
string identifier for custom sink types:

| Atom | String | Storage backend |
|---|---|---|
| `:mongodb` | `"MongoDB"` | MongoDB (default) |
| `:sql` | `"SQL"` | SQL database |
| `:in_memory` | `"InMemory"` | In-process memory only |
| `:not_set` | `"NotSet"` | No sink — read model is not persisted |

The configured sink applies to **all** projections and reducers registered by
that client instance. There is no per-read-model sink override at this time.

## Multiple clients with different sinks

If your application needs some read models in MongoDB and others in SQL, start
two separate `Chronicle.Client` instances with different names and assign the
relevant read models to each:

```elixir
children = [
  {Chronicle.Client,
   name: :mongo_client,
   connection_string: "chronicle://localhost:35000",
   event_store: "store",
   default_sink_type_id: :mongodb,
   read_models: [MyApp.ReadModels.AccountSummary]},

  {Chronicle.Client,
   name: :sql_client,
   connection_string: "chronicle://localhost:35000",
   event_store: "store",
   default_sink_type_id: :sql,
   read_models: [MyApp.ReadModels.AccountReport]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

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
| `WellKnownSinkTypes.not_set/0` | `"NotSet"` |
| `WellKnownSinkTypes.resolve/1` | Resolves an atom or passthrough string |

`resolve/1` is used internally by `Chronicle.Client` to normalise the
`:default_sink_type_id` option. You rarely need to call it directly, but it is
useful when building custom tooling or test helpers:

```elixir
alias Chronicle.Sinks.WellKnownSinkTypes

WellKnownSinkTypes.resolve(:mongodb)    # => "MongoDB"
WellKnownSinkTypes.resolve(:sql)        # => "SQL"
WellKnownSinkTypes.resolve("Custom")    # => "Custom"
```
