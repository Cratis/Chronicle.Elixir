---
sharedTopicBridge: true
---

# Read Models

Read models are shared Chronicle concepts. Querying, snapshots, watching, and consistency are documented in the shared Chronicle section.

- [Read models](/chronicle/read-models/)
- [Getting a single read model](/chronicle/read-models/getting-single-instance/)
- [Getting read model collections](/chronicle/read-models/getting-collection-instances/)
- [Elixir client setup](./get-started.md)

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
