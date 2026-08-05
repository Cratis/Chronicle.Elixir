---
sharedTopicBridge: true
---

# Event Sequences

Event sequences are a shared Chronicle concept. Use the shared docs for the event log, custom sequences, filtering, and appending behavior.

- [Event sequence concept](/chronicle/concepts/event-sequence/)
- [Events and event logs](/chronicle/events/)
- [Appending events](/chronicle/events/appending/)
- [Elixir client setup](./get-started.md)

The sections below cover `Chronicle.EventSequences.EventLog` APIs that are new to the
Elixir client and not yet covered by the shared docs above.

## Redacting events

Redaction permanently erases an event's content for compliance/GDPR erasure. Unlike
compliance encryption (reversible via key rotation), this overwrites the event's content
in the log for good. Mirrors the C# and TypeScript clients' `IEventSequence.Redact()`.

Redact a single event by its sequence number, with a reason:

```elixir
:ok = Chronicle.EventSequences.EventLog.redact(sequence_number, "Customer requested erasure")
```

Redact every event for an event source in one call — for example, to erase all data for a
specific user:

```elixir
:ok =
  Chronicle.EventSequences.EventLog.redact_for_event_source(
    event_source_id,
    "Account closed under GDPR"
  )
```

Narrow a bulk redaction to specific event types by passing a list of event type modules as
the third argument:

```elixir
:ok =
  Chronicle.EventSequences.EventLog.redact_for_event_source(
    event_source_id,
    "Email address was captured in error",
    [MyApp.Events.EmailChanged]
  )
```

Both functions accept the same options as `append/3` (`:client`, `:namespace`,
`:event_sequence_id`).

## Reading forward from a sequence number

`get_from_sequence_number/2` returns events from (and including) a given sequence number
onward, optionally filtered by event source id and event types. Mirrors the C# and
TypeScript clients' `GetFromSequenceNumber()`.

```elixir
{:ok, events} =
  Chronicle.EventSequences.EventLog.get_from_sequence_number(sequence_number,
    event_source_id: event_source_id,
    event_types: [MyApp.Events.OrderPlaced]
  )
```

## Sequence numbers

`get_tail_sequence_number/2` returns the sequence number of the last appended event.
`get_next_sequence_number/2` mirrors it but returns the number that will be assigned to the
**next** appended event — it distinguishes "the log is empty" (returns `0`) from "the tail
is at sequence `0`" (returns `1`), which `get_tail_sequence_number/2` alone cannot do.
Mirrors the C# and TypeScript clients' `GetNextSequenceNumber()`.

```elixir
{:ok, tail} = Chronicle.EventSequences.EventLog.get_tail_sequence_number(event_source_id)
{:ok, next} = Chronicle.EventSequences.EventLog.get_next_sequence_number(event_source_id)
```

`get_tail_sequence_number_for_observer/2` scopes the tail lookup to only the event types a
reactor or reducer module subscribes to (its `@handles` declarations), instead of every
event type. Mirrors the C# client's `GetTailSequenceNumberForObserver()`.

```elixir
{:ok, tail} =
  Chronicle.EventSequences.EventLog.get_tail_sequence_number_for_observer(
    MyApp.Reactors.OrderNotifier
  )
```

## Filtering by stream

`get_for_event_source/2` and `get_tail_sequence_number/2` also accept `:event_source_type`,
`:event_stream_type`, and `:event_stream_id` options, narrowing either call to a specific
non-default stream instead of silently ignoring these dimensions:

```elixir
{:ok, events} =
  Chronicle.EventSequences.EventLog.get_for_event_source(event_source_id,
    event_stream_type: "audit-trail",
    event_stream_id: "2024"
  )
```

## Completing a stream

`complete_stream/3` closes a named, non-default stream so that no further events can be
appended to it. The default stream can never be completed.

```elixir
case Chronicle.EventSequences.EventLog.complete_stream("audit-trail", "2024") do
  {:ok, tail_sequence_number} -> :ok
  {:error, :default_stream_cannot_be_completed} -> :error
  {:error, :already_completed} -> :ok
end
```

## Appending and waiting for observer completion

`append_and_wait_for_completion/3` appends a single event and then waits (default: 5
seconds) for every observer affected by the append — reactors, reducers, projections — to
either reach the appended sequence number or fail, instead of returning as soon as the
event is durably stored. Mirrors the C# client's `AppendResult.WaitForCompletion()`.

```elixir
case Chronicle.EventSequences.EventLog.append_and_wait_for_completion(
       event_source_id,
       %MyApp.Events.OrderPlaced{customer_id: customer_id, total: total}
     ) do
  {:ok, %{success: true, failed_partitions: []}} ->
    :ok

  {:ok, %{success: false, failed_partitions: failed_partitions}} ->
    # One or more observers failed or timed out — inspect failed_partitions
    # (a list of `Chronicle.FailedPartitions.FailedPartition`).
    :error

  {:error, reason} ->
    :error
end
```

Pass `:timeout` (milliseconds) to override the default wait.
