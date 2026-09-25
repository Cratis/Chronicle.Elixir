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
