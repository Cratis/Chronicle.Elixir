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

Redaction permanently erases an event's content, for example to honor a GDPR erasure
request. It works on events, not on keys: [compliance](/chronicle/compliance/) encrypts
PII and makes it unreadable by deleting a subject's key, while redaction overwrites the
stored event itself. Neither can be undone. Mirrors the C# and TypeScript clients' `IEventSequence.Redact()`.

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

Both functions accept `:client`, `:namespace` and `:event_sequence_id`, plus the
`:correlation_id`, `:identity` and `:causation` context overrides described in
[Context management](context.md). They ignore the other `append/3` options, such as
`:tags`, `:subject` and `:concurrency_scope`.

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

The list holds the generated contract structs,
`%Cratis.Chronicle.Contracts.Sequences.AppendedEventResponse{}`, not your event structs.
Each carries its metadata in `Context` and the event's JSON in its content field.

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

Leaving `:event_source_type` and `:event_stream_type` out looks across every source and stream type. Version 3.5.0 narrowed an omitted value to `"Default"` and returned `{:ok, 0}` however many events were stored; upgrade to 3.5.1 or later.

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
  {:ok, _tail_sequence_number} -> :ok
  {:error, :default_stream_cannot_be_completed} -> :error
  {:error, :already_completed} -> :ok
  {:error, reason} -> {:error, reason}
end
```

The last clause covers transport errors such as `{:error, :not_connected}`.

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

  {:ok, %{success: false, failed_partitions: _failed_partitions}} ->
    # One or more observers failed on the event — inspect failed_partitions
    # (a list of `Chronicle.FailedPartitions.FailedPartition`).
    :error

  {:error, reason} ->
    # The append failed, or it succeeded and the wait failed. See below.
    {:error, reason}
end
```

Pass `:timeout` (milliseconds) to override the default wait.

Read the three outcomes carefully, because an error doesn't always mean the event wasn't
stored:

- `{:ok, %{success: true}}`: the event is stored and every affected observer has processed it.
- `{:ok, %{success: false, failed_partitions: ...}}`: the event is stored, but at least one
  observer failed on it.
- `{:error, reason}`: either the append failed, or the append succeeded and the wait itself
  failed. A wait that runs past the gRPC deadline returns
  `{:error, %GRPC.RPCError{status: 4, message: "Deadline Exceeded"}}` even though the event
  is stored. Don't retry the append blindly on `{:error, _}`; check the event log or use a
  [concurrency scope](/chronicle/events/concurrency/) so a retry can't store the event twice.

There is no append-many variant: waiting after `append_many/3` isn't supported.

## Append results

`append/3` and `append_many/3` return `:ok` or `{:error, reason}`. When you need the sequence
number that was assigned, or the *structured* reason an append was refused, use the `_with_result`
variants. They return a `Chronicle.EventSequences.AppendResult`; mirrors the .NET `AppendResult`
and `AppendManyResult`.

```elixir
case Chronicle.append_with_result("user-1", %MyApp.Events.UserRegistered{email: "a@b.c"}) do
  {:ok, %{sequence_number: sequence_number}} ->
    {:registered, sequence_number}

  {:error, %{constraint_violations: [violation | _]}} ->
    {:rejected, violation.constraint_name, violation.message}

  {:error, %{concurrency_violations: [violation | _]}} ->
    {:conflict, violation.expected_sequence_number, violation.actual_sequence_number}

  {:error, other} ->
    {:error, other}
end
```

`append_many_with_result/3` returns every assigned sequence number in order. A rejection is
`{:error, %AppendResult{}}` carrying `:constraint_violations` (each with `:constraint_name`,
`:message`, `:event_type_id`, `:sequence_number` and `:details`), `:concurrency_violations` (each
with `:event_source_id`, `:expected_sequence_number` and `:actual_sequence_number`) and `:errors`.
Transport failures stay plain `{:error, reason}` terms.

To wait until the observers have processed what you appended, call
`Chronicle.EventSequences.AppendResult.wait_for_completion/2` on a successful result.

## Reading typed events

`get_for_event_source/3` and `get_from_sequence_number/2` return the raw wire events. Pass
`decode: true` to get `Chronicle.Events.AppendedEvent` structs instead, whose `:event` is the event
struct you appended:

```elixir
{:ok, events} =
  Chronicle.EventSequences.EventLog.get_for_event_source("acc-1", decode: true)

for %{event: %MyApp.Events.FundsDeposited{amount: amount}, context: context} <- events do
  IO.puts("#{amount} deposited by #{context.caused_by.name} at sequence #{context.sequence_number}")
end
```

An event of a type this client does not know has `event: nil` and the decoded payload in `:raw`;
a redacted event has `redacted?: true` and a `:redaction` with the reason. Nested structs,
lists of structs and maps decode as described in `Chronicle.Serialization`.

## Event context

Reactors, reducers and `decode: true` reads all give you a `Chronicle.Events.EventContext`:
the event type and source, sequence number, `occurred`, event store and namespace,
`correlation_id`, the identity that caused the event (`caused_by`, with `on_behalf_of`), the
`causation` chain, `tags`, `hash` and `subject`. See [Context management](context.md) for how to
set the correlation id, identity and causation on the way in.

## Creation-only guards

`Chronicle.Events.ConcurrencyScope.expecting_no_matching_event/1` refuses an append when a
matching event already exists - the guard for "this can only happen once":

```elixir
scope =
  Chronicle.Events.ConcurrencyScope.expecting_no_matching_event(
    event_source_id: true,
    event_types: [MyApp.Events.UserRegistered]
  )

Chronicle.append("user-1", %MyApp.Events.UserRegistered{}, concurrency_scope: scope)
```

It sends the kernel's explicit no-matching-event condition. Leaving the expected sequence number
unset is not a substitute: that turns the check off.

## Streams, metadata and verification

`Chronicle.EventSequences.Streams` closes, reopens and inspects stream scopes, reads event
metadata and verifies stored content:

```elixir
alias Chronicle.EventSequences.Streams

{:ok, sequence_number} = Streams.complete_scope(event_source_id: "acc-1", event_stream_type: "Period", event_stream_id: "2024")
{:ok, true} = Streams.scope_completed?(event_source_id: "acc-1", event_stream_type: "Period", event_stream_id: "2024")
{:ok, closed} = Streams.closed(event_source_id: "acc-1")
:ok = Streams.reopen_scope("Late invoice arrived", event_source_id: "acc-1", event_stream_type: "Period", event_stream_id: "2024")

{:ok, [metadata]} = Streams.get_metadata([sequence_number])
{:ok, :equal} = Streams.verify_content(sequence_number, %MyApp.Events.PeriodClosed{period: "2024"})
```

Events that close a scope as part of their own append are declared with
`closes_stream`; see [Constraints](constraints.md#closing-events).

## Payload size

The kernel refuses a message larger than 4 MiB. Sending one used to break the connection every
observer shares, so the client now checks first and returns
`{:error, {:payload_too_large, size, limit}}`. A reducer whose read model outgrows the limit
reports the reduction as failed instead. Raise or disable the guard with
`config :cratis_chronicle, max_payload_bytes: 8 * 1024 * 1024` (or `:infinity`) if your kernel is
configured for larger messages.

