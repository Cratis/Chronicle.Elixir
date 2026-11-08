---
title: Failed partitions
description: Find the event sources where a reactor or reducer failed, then read each failed attempt and its error details from Elixir to diagnose the problem.
---

`Chronicle.FailedPartitions` provides an idiomatic Elixir API for inspecting Chronicle's
failed partitions.

A partition (an event source, within an observer's subscription) is marked failed when an
observer can't handle one of its events. In the Elixir client that happens when:

- a reactor's `handle/2` returns `{:error, reason}`, raises, or returns a side effect that
  can't be appended;
- a reducer's `reduce/3` raises. A reducer must return the new model; returning
  `{:error, reason}` doesn't mark a failure, so raise instead.

A failed partition stops advancing while the rest of the observer continues. Mirrors the C#
and Kotlin clients' `IFailedPartitions`.

Inspect failures in the selected client's event store and namespace before choosing a recovery operation.
Use [Recovering a partition](observers.md#recovering-a-partition) for the recovery request; a lookup is not recovery.
Review messages and stack traces before sharing diagnostics.

## Starting point

Start `Chronicle.Client` first:

```elixir
children = [
  {Chronicle.Client,
    connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
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

See [Observers](observers.md) for the observer's own state — including removing one whose
declaring code is gone, which also clears any failed partitions kept for it.
