# Chronicle Elixir Concurrency Scope

`Chronicle.Events.ConcurrencyScope` lets you make append operations conditional on the current tail of an event sequence.
This is useful for optimistic concurrency when multiple processes may append to the same event source, stream, or subset of event types.

## Why concurrency scope exists

Chronicle stores events in ordered event sequences.
A concurrency scope says:

- "I expect the tail sequence number to still be `N`"
- and optionally
- "Only consider events for this event source, stream, source type, or these event types"

If the scoped tail has changed before your append reaches Chronicle, the append fails instead of silently writing against stale state.

## The module

```elixir
alias Chronicle.Events.ConcurrencyScope
```

Create a scope explicitly:

```elixir
scope =
  ConcurrencyScope.new(12,
    event_source_id: true,
    event_stream_type: "accounting",
    event_stream_id: "primary",
    event_source_type: "account",
    event_types: [MyApp.Events.FundsDeposited, MyApp.Events.FundsWithdrawn]
  )
```

Or use the event-source helper:

```elixir
scope = ConcurrencyScope.for_event_source(12)
```

To represent no explicit concurrency constraint:

```elixir
scope = ConcurrencyScope.none()
```

## Scope fields

- `sequence_number` — the expected tail sequence number for the scoped sequence
- `event_source_id` — when `true`, include the append call's event source id in the concurrency check
- `event_stream_type` — restrict the check to a specific event stream type
- `event_stream_id` — restrict the check to a specific event stream id
- `event_source_type` — restrict the check to a specific event source type
- `event_types` — restrict the check to specific Chronicle event type modules

> `event_source_id` is a boolean because the actual event source id is already supplied to `Chronicle.append/3` or `Chronicle.append_many/3`.

## Single-event append

```elixir
alias Chronicle.Events.ConcurrencyScope

{:ok, tail} = Chronicle.get_tail_sequence_number("account-42")

scope = ConcurrencyScope.for_event_source(tail)

:ok =
  Chronicle.append("account-42", %MyApp.Events.FundsDeposited{
    account_id: "account-42",
    amount: 500
  },
    concurrency_scope: scope
  )
```

You can also pass keyword options instead of constructing the struct yourself:

```elixir
:ok =
  Chronicle.append("account-42", event,
    concurrency_scope: [
      sequence_number: tail,
      event_source_id: true,
      event_types: [MyApp.Events.FundsDeposited]
    ]
  )
```

## Batch append with `append_many/3`

`append_many/3` applies the concurrency scope to the batch append operation.
This is useful when you want to append multiple events atomically, but only if the scoped tail is still where you expect it to be.

```elixir
{:ok, tail} = Chronicle.get_tail_sequence_number("account-42")

scope = ConcurrencyScope.for_event_source(tail)

:ok =
  Chronicle.append_many("account-42", [
    %MyApp.Events.FundsDeposited{account_id: "account-42", amount: 500},
    %MyApp.Events.FundsWithdrawn{account_id: "account-42", amount: 200}
  ],
    concurrency_scope: scope
  )
```

## Common optimistic concurrency flow

1. Read current state or tail sequence number.
2. Build a concurrency scope from that tail.
3. Attempt the append.
4. If the append fails, re-read state and decide whether to retry.

Example:

```elixir
{:ok, tail} = Chronicle.get_tail_sequence_number("account-42")

scope = ConcurrencyScope.for_event_source(tail)

case Chronicle.append("account-42", event, concurrency_scope: scope) do
  :ok ->
    :ok

  {:error, {:constraint_violations, violations}} ->
    {:error, {:stale_write, violations}}

  {:error, reason} ->
    {:error, reason}
end
```

## Event-type scoped concurrency

You can scope concurrency checks to a subset of event types when only certain events should participate in the optimistic concurrency boundary.

```elixir
scope =
  ConcurrencyScope.for_event_source(tail,
    event_types: [
      MyApp.Events.FundsDeposited,
      MyApp.Events.FundsWithdrawn
    ]
  )
```

In this case, Chronicle checks the tail based on those event types inside the selected scope instead of every event in the sequence.

## Default behavior

If you do not pass `:concurrency_scope`, Chronicle uses `Chronicle.Events.ConcurrencyScope.none/0`, which means the append is not guarded by an explicit optimistic concurrency check.
