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

## Recovering a partition

```elixir
{:ok, :started} = Chronicle.Observers.retry_partition(MyApp.Reactors.OrderNotifier, "order-1")
{:ok, %{outcome: :cleared, retry_outcome: :started}} =
  Chronicle.Observers.clear_partition_quarantine(MyApp.Reactors.OrderNotifier, "order-1")
:ok = Chronicle.Observers.clear_observer_quarantine(MyApp.Reactors.OrderNotifier)
```

The first argument is an observer id or a reactor, reducer or projection module. `retry_partition/3`
returns `:started`, `:partition_not_found`, `:observer_quarantined` or `:partition_quarantined`
(clear the quarantine first). `clear_partition_quarantine/3` retries immediately unless you pass
`retry_immediately: false`.

## Lag

An observer that was evicted or stalled is invisible from the append side. `Chronicle.Observers.Lag.measure/1`
returns, per observer, the distance between the tail of the event sequence and the last event it
handled. Start the reporter to publish it as telemetry:

```elixir
{Chronicle.Client, observer_lag: [interval: 15_000], ...}

:telemetry.attach("lag", [:chronicle, :observer, :lag], fn _, %{lag: lag}, %{observer_id: id}, _ ->
  if lag > 1_000, do: Logger.warning("#{id} is #{lag} events behind")
end, nil)
```
