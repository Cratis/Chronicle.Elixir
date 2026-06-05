# Read Models

`Chronicle.ReadModels` is the Elixir query interface for Chronicle read models.
It follows the same overall shape as the C# and TypeScript `IReadModels` APIs while exposing idiomatic Elixir return values.

## What a read model is

A read model is queryable state derived from events.
In Chronicle.Elixir, read models are usually backed by either:

- a model-bound projection declared with `use Chronicle.ReadModel`
- a reducer declared with `use Chronicle.Reducer`

Once `Chronicle.Client` has registered the artifacts, use `Chronicle.ReadModels` to inspect the current state, browse all instances, page through materialized data, or inspect historical snapshots.

## API overview

### Get one instance by key

```elixir
{:ok, account} = Chronicle.ReadModels.get(MyApp.ReadModels.Account, "account-42")
{:ok, account} = Chronicle.ReadModels.get_instance_by_id(MyApp.ReadModels.Account, "account-42")
```

Both functions call the same Chronicle API. `get/3` is the concise Elixir helper, while `get_instance_by_id/3` mirrors the naming used by the other Chronicle clients.

Use `:session_id` when you need a session-scoped read model:

```elixir
{:ok, account} =
  Chronicle.ReadModels.get_instance_by_id(
    MyApp.ReadModels.Account,
    "account-42",
    session_id: "session-42"
  )
```

Returns `{:ok, nil}` when the read model does not exist.

### Get all instances by replaying the event sequence

```elixir
{:ok, accounts} = Chronicle.ReadModels.all(MyApp.ReadModels.Account)

{:ok, accounts} =
  Chronicle.ReadModels.get_instances(
    MyApp.ReadModels.Account,
    event_count: 1_000
  )
```

This uses Chronicle's replay-oriented `GetAllInstances` operation.
It matches the `GetInstances<TReadModel>()` concept from the C# and TypeScript clients.

#### Options

- `:event_count` — limit how many events Chronicle processes during replay
- `:event_sequence_id` — use a non-default event sequence

### Query the materialized read-model container

```elixir
{:ok, result} =
  Chronicle.ReadModels.query(
    MyApp.ReadModels.Account,
    page: 1,
    page_size: 25
  )

result.instances
result.total_count
result.page
result.page_size
```

`query/2` is different from `all/2`:

- `all/2` replays the event sequence
- `query/2` queries the materialized read-model store directly

Use `query/2` when you need paging, counts, or want to inspect a specific occurrence/container.

#### Query options

- `:page` — page number, default `1`
- `:page_size` — page size, default `50`
- `:occurrence` — optional occurrence/container name for replayed read models

### Get historical snapshots for one key

```elixir
{:ok, snapshots} =
  Chronicle.ReadModels.snapshots(
    MyApp.ReadModels.Account,
    "account-42"
  )
```

Or with the cross-client naming:

```elixir
{:ok, snapshots} =
  Chronicle.ReadModels.get_snapshots_by_id(
    MyApp.ReadModels.Account,
    "account-42"
  )
```

Each snapshot is returned as `%Chronicle.ReadModels.Snapshot{}` with:

- `:read_model` — decoded Elixir struct for that point in time
- `:events` — raw Chronicle appended-event payloads that produced the snapshot
- `:occurred` — parsed `DateTime` when available
- `:correlation_id` — the correlation identifier from Chronicle

### Get replay occurrences

```elixir
{:ok, occurrences} = Chronicle.ReadModels.occurrences(MyApp.ReadModels.Account)
```

Each occurrence is returned as `%Chronicle.ReadModels.Occurrence{}` and describes a replayed version of the read model, including the observer id, when it occurred, and the container names involved.

### Get registered definitions

```elixir
{:ok, definitions} = Chronicle.ReadModels.definitions()
```

Each definition is returned as `%Chronicle.ReadModels.Definition{}` with:

- read-model identifier and generation
- container/display names
- schema JSON
- index property paths
- observer type (`:projection` or `:reducer`)
- observer identifier
- owner/source metadata
- sink metadata

This is useful for diagnostics, tooling, or documentation generation.

## Shared options

Most functions accept:

- `:client` — named client to use instead of `Chronicle.Client`
- `:namespace` — override the configured namespace

Replay-oriented functions also accept:

- `:event_sequence_id` — defaults to `"event-log"`

## Returned structs

### `%Chronicle.ReadModels.QueryResult{}`

Returned by `query/2`.

- `:instances`
- `:total_count`
- `:page`
- `:page_size`

### `%Chronicle.ReadModels.Snapshot{}`

Returned by `snapshots/3` and `get_snapshots_by_id/3`.

### `%Chronicle.ReadModels.Occurrence{}`

Returned by `occurrences/2` and `get_occurrences/2`.

### `%Chronicle.ReadModels.Definition{}`

Returned by `definitions/1` and `get_definitions/1`.

## Top-level Chronicle helpers

The main `Chronicle` module keeps the convenience helpers for the most common read-model calls:

```elixir
{:ok, account} = Chronicle.read_model(MyApp.ReadModels.Account, "account-42")
{:ok, accounts} = Chronicle.all(MyApp.ReadModels.Account)
```

For paging, definitions, occurrences, and snapshots, use `Chronicle.ReadModels` directly.

## Example

```elixir
alias MyApp.ReadModels.Account

{:ok, account} = Chronicle.ReadModels.get(Account, "account-42")
{:ok, all_accounts} = Chronicle.ReadModels.get_instances(Account)
{:ok, page} = Chronicle.ReadModels.query(Account, page: 1, page_size: 10)
{:ok, snapshots} = Chronicle.ReadModels.get_snapshots_by_id(Account, "account-42")
{:ok, occurrences} = Chronicle.ReadModels.get_occurrences(Account)
{:ok, definitions} = Chronicle.ReadModels.get_definitions()
```

See `Samples/console` for a runnable end-to-end example that seeds employees, folds employee lifecycle events into the reducer-backed `EmployeeState` read model, and also reads a customer compliance model.
