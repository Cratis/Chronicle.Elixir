# Failed Partitions

`Chronicle.FailedPartitions` provides an idiomatic Elixir API for inspecting Chronicle's
failed partitions.

A partition (an event source, within an observer's subscription) is marked failed when a
reactor, reducer, or other observer's handling of an event raises or returns an error.
Failed partitions stop advancing until they are retried or the observer is replayed.
Mirrors the C# and Kotlin clients' `IFailedPartitions`.

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

## Getting all failed partitions

Get every failed partition for any observer (reactor, reducer, and so on) on the current
event store:

```elixir
{:ok, failed_partitions} = Chronicle.FailedPartitions.get_all()
```

## Getting failed partitions for a specific observer

Narrow the lookup to a single observer by its id:

```elixir
{:ok, failed_partitions} = Chronicle.FailedPartitions.get_for("MyApp.Reactors.OrderNotifier")
```

## The `FailedPartition` and `Attempt` structs

Each failed partition is returned as `%Chronicle.FailedPartitions.FailedPartition{}` with:

- `:id`
- `:observer_id`
- `:partition` — the event source id that failed
- `:attempts` — the list of failed attempts, oldest first

Each attempt is a `%Chronicle.FailedPartitions.Attempt{}` with:

- `:occurred`
- `:sequence_number`
- `:messages`
- `:stack_trace`

```elixir
Enum.each(failed_partitions, fn failed_partition ->
  IO.puts("#{failed_partition.observer_id}: #{failed_partition.partition}")

  Enum.each(failed_partition.attempts, fn attempt ->
    IO.puts("  ##{attempt.sequence_number}: #{Enum.join(attempt.messages, "; ")}")
  end)
end)
```

## Using a named client

```elixir
{:ok, failed_partitions} = Chronicle.FailedPartitions.get_all(client: :bank_chronicle)
```
