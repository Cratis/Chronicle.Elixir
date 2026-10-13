---
sharedTopicBridge: true
---

# Read Models

Read models are shared Chronicle concepts. Querying, snapshots, watching, and consistency are documented in the shared Chronicle section.

- [Read models](/chronicle/read-models/)
- [Getting a single read model](/chronicle/read-models/getting-single-instance/)
- [Getting read model collections](/chronicle/read-models/getting-collection-instances/)
- [Elixir client setup](./get-started.md)

## Missing and not-yet-projected read models

`Chronicle.read_model/3`, and `Chronicle.ReadModels.get/3` which it calls, return `{:ok, nil}`
when no instance exists for the key. That is also what you get right after an append whose
projection hasn't run yet, because Chronicle projects asynchronously:

```elixir
case Chronicle.read_model(MyApp.ReadModels.AccountInfo, account_id) do
  {:ok, nil} -> :not_found_or_not_projected_yet
  {:ok, account} -> {:ok, account}
  {:error, reason} -> {:error, reason}
end
```

When you need to read your own write, append with
`Chronicle.EventSequences.EventLog.append_and_wait_for_completion/3`, which returns once the
affected observers have processed the event. See
[Event sequences](./event-sequences.md#appending-and-waiting-for-observer-completion).

## Watching for live changes

`Chronicle.ReadModels.watch/2` subscribes the calling process to live changesets for a read
model over the kernel's server-streaming `Watch` RPC. Elixir has no `IObservable`/
async-iterable equivalent to the C# and TypeScript clients' `Watch<TReadModel>()`, so this
follows the same message-based idiom as `Chronicle.Connections.Lifecycle.subscribe/1`.

```elixir
{:ok, watcher} = Chronicle.ReadModels.watch(MyApp.ReadModels.AccountInfo)

receive do
  {:chronicle_read_model_changed, MyApp.ReadModels.AccountInfo, changeset} ->
    # changeset is a %Chronicle.ReadModels.Changeset{} with :model_key, :read_model,
    # :change_type (:added | :modified | :removed), :event_sequence_number, and more.
    IO.inspect(changeset.read_model)

  {:chronicle_read_model_watch_error, MyApp.ReadModels.AccountInfo, reason} ->
    # The stream failed and the watch has ended — call watch/2 again to resume.
    IO.inspect(reason)
end

Chronicle.ReadModels.unwatch(watcher)
```

## Dehydrating a session

A read-model session (created implicitly whenever you read with a `:session_id`) normally
expires on its own. `dehydrate_session/4` explicitly cleans one up once the caller is done
with it, releasing the resources Chronicle held for it right away.

```elixir
:ok =
  Chronicle.ReadModels.dehydrate_session(
    MyApp.ReadModels.AccountInfo,
    account_id,
    session_id
  )
```

## Filtering and sorting

`Chronicle.ReadModels.query/2` accepts `:filter` and `:sort`. All conditions must match; a condition
is a value (equality) or one of `{:gt, v}`, `{:gte, v}`, `{:lt, v}`, `{:lte, v}`, `{:ne, v}`,
`{:in, [v]}`, `{:contains, v}`:

```elixir
{:ok, result} =
  Chronicle.ReadModels.query(MyApp.ReadModels.Entry,
    filter: [schema_id: "invoice", amount: {:gt, 100}],
    sort: {:amount, :desc},
    page_size: 20
  )

result.total_count   # the number of *matching* instances
```

An unknown field returns `{:error, {:unknown_field, field}}`.

**The filter is applied by the client.** The kernel's query contract pages instances but cannot
filter them, so the client pages through the read model and evaluates the filter itself. That is
right for read models of modest size. A read model with more than `:max_scan` instances (default
`10_000`) returns `{:error, {:scan_limit_exceeded, max_scan}}` rather than a silently partial
answer. For large data, give the question its own projection.

## Observing a collection

`Chronicle.ReadModels.observe/2` sends the calling process the page of instances now and again each
time it changes:

```elixir
{:ok, observer} = Chronicle.ReadModels.observe(MyApp.ReadModels.AccountInfo, page_size: 25)

receive do
  {:chronicle_read_model_instances, MyApp.ReadModels.AccountInfo, %{instances: accounts}} -> accounts
end

Chronicle.ReadModels.unobserve(observer)
```

An error arrives as `{:chronicle_read_model_observe_error, model, reason}` and ends the observation;
call `observe/2` again to resume. `watch/2` remains the tool for the changes of one instance.

## Read model reactors

A `Chronicle.ReadModels.Reactor` reacts to *changes of a read model* rather than to events:

```elixir
defmodule MyApp.Reactors.BalanceWatcher do
  use Chronicle.ReadModels.Reactor, model: MyApp.ReadModels.AccountInfo

  @impl true
  def on_modified(account, _changeset) do
    if account.balance < 0, do: Alerts.overdrawn(account)
    :ok
  end
end

{Chronicle.Client, read_model_reactors: [MyApp.Reactors.BalanceWatcher], ...}
```

`on_added/2`, `on_modified/2` and `on_removed/2` are all optional. The reactor receives changes that
happen while it runs and re-establishes its watch after a reconnect.

## Map fields and nested structs

A field whose default is a plain map (`parameters: %{}`) is registered as an object, its keys kept
exactly as you wrote them. Nested structs keep their multi-word field names. Fields that default to
`nil`, or hold a list of structs, are declared with `types:`:

```elixir
use Chronicle.ReadModels.ReadModel,
  types: [lines: {:list, MyApp.OrderLine}, address: MyApp.Address, labels: :map]
```

See `Chronicle.Serialization`.
