# Observers

`Chronicle.Observers` provides an idiomatic Elixir API for working with Chronicle observers.

An observer is a reactor, reducer, or projection registered against an event sequence to be told
about the events it cares about. This module is how an application finds out what the event
store knows about its observers, and how it removes one whose declaring code is gone.
Mirrors the C#, Kotlin, and TypeScript clients' `IObservers`.

## Starting point

Start `Chronicle.Client` first:

```elixir
children = [
  {Chronicle.Client,
    connection_string: "chronicle://localhost:35000",
    event_store: "banking",
    otp_app: :my_app}
]
```

## Getting all observers

Get every observer registered in the event store's current namespace:

```elixir
{:ok, observers} = Chronicle.Observers.get_all()
```

## The `ObserverInformation` struct

Each observer is returned as `%Chronicle.Observers.ObserverInformation{}` with:

- `:id`
- `:event_sequence_id` — the event sequence the observer observes
- `:type` — `:reactor`, `:projection`, `:reducer`, `:external`, or `:unknown`
- `:running_state` — `:active`, `:suspended`, `:replaying`, `:disconnected`, `:quarantined`, or `:unknown`
- `:last_handled_event_sequence_number`
- `:next_event_sequence_number`
- `:handled_event_count`

```elixir
Enum.each(observers, fn observer ->
  IO.puts("#{observer.id} (#{observer.type}) is #{observer.running_state}")
end)
```

## Removing an observer whose declaring code is gone

Deleting a read model and its projection, or removing a reactor, does not remove what it
registered. The observer stays behind, settles into `:disconnected`, and keeps its definition,
state, handled counts, and failed partitions in the event store forever — until something
removes them.

```elixir
{:ok, result} = Chronicle.Observers.remove("MyApp.Reactors.OrderNotifier")

if Chronicle.Observers.RemovalResult.removed?(result) do
  IO.puts("Removed.")
else
  IO.puts("Refused: #{result.outcome} (#{result.blocking_namespace})")
end
```

Removal covers the whole event store, not just the current namespace: an observer's definition,
and its projection definition where it has one, are store-level records shared by every
namespace. `remove/2` refuses while the observer is running or still has a subscribed client in
*any* namespace, and `blocking_namespace` names the one that blocked it, since the guard runs
across all of them. **There is no override** — stop the declaring application first if the intent
is to remove a live observer. Read model data and sink containers are left untouched; only the
observer's own bookkeeping goes.

## Using a named client

```elixir
{:ok, observers} = Chronicle.Observers.get_all(client: :bank_chronicle)
{:ok, result} = Chronicle.Observers.remove("MyApp.Reactors.OrderNotifier", client: :bank_chronicle)
```
