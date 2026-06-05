# Event Sequences

Event Sequences allow you to organize events into separate logical streams within an event source. By default, all events go to the `"event-log"` sequence, but you can append events to and query from other named sequences.

## Overview

An event sequence is a separate, ordered stream of events for a given event source. Common use cases include:

- **Audit logs** — separate sequence for all changes
- **Domain events** — sequence for business domain events
- **Integration events** — sequence for events published to external systems
- **Compensating events** — sequence for undo/compensation operations

## Appending to Event Sequences

### Default Event Sequence

By default, `Chronicle.append/3` appends to the `"event-log"` sequence:

```elixir
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})
# Goes to "event-log" sequence
```

### Named Event Sequences

Append to a different sequence using the `:event_sequence_id` option:

```elixir
:ok = Chronicle.append("account-42", 
  %MyApp.Events.FundsDeposited{amount: 100},
  event_sequence_id: "audit-log"
)

:ok = Chronicle.append("account-42",
  %MyApp.Events.FundsDeposited{amount: 100},
  event_sequence_id: "domain-events"
)
```

### Multiple Events

When appending multiple events at once, they go to the same sequence:

```elixir
events = [
  %MyApp.Events.FundsDeposited{amount: 100},
  %MyApp.Events.FundsDeposited{amount: 50}
]

:ok = Chronicle.append_many("account-42", events, event_sequence_id: "audit-log")
```

## Querying Event Sequences

### Default Sequence

Query events from the default `"event-log"` sequence:

```elixir
{:ok, events} = Chronicle.EventLog.get_for_event_source("account-42")
```

### Named Sequences

Query events from a specific sequence:

```elixir
{:ok, audit_events} = Chronicle.EventLog.get_for_event_source("account-42",
  event_sequence_id: "audit-log"
)

{:ok, domain_events} = Chronicle.EventLog.get_for_event_source("account-42",
  event_sequence_id: "domain-events"
)
```

### Event Sequence Tail

Get the sequence number of the last event in a sequence:

```elixir
# Tail of default "event-log"
{:ok, tail_seq} = Chronicle.get_tail_sequence_number("account-42")

# Tail of specific sequence
{:ok, tail_seq} = Chronicle.get_tail_sequence_number("account-42",
  event_sequence_id: "audit-log"
)

# Check if any events exist (tail will be > 0 if events exist)
{:ok, tail_seq} = Chronicle.get_tail_sequence_number("account-42")
has_events? = tail_seq > 0
```

### Check for Events

Check whether any events exist in a sequence:

```elixir
# Check default sequence
{:ok, has_events?} = Chronicle.has_events_for?("account-42")

# Check specific sequence
{:ok, has_events?} = Chronicle.has_events_for?("account-42",
  event_sequence_id: "audit-log"
)
```

## Event Sequences and Read Models

Read models work primarily with the default `"event-log"` sequence. To project events from other sequences, you would need custom projection logic or a reactor that listens to those sequences.

### Projections with Event Sequences

Currently, model-bound projections implicitly work with `"event-log"`. If you need to project from other sequences, use a reactor instead:

```elixir
defmodule MyApp.Reactors.AuditReactor do
  use Chronicle.Reactor

  @handles MyApp.Events.FundsDeposited

  @impl true
  def handle(%MyApp.Events.FundsDeposited{} = event, context) do
    # This reactor processes events from the default sequence
    # To listen to a specific sequence, you would need Chronicle 
    # server-side filtering (feature varies by Chronicle version)
    IO.inspect({:audit, event})
    :ok
  end
end
```

## Typical Use Cases

### Example: Dual Event Streams

```elixir
defmodule BankingApp.Services.TransactionService do
  alias Chronicle.EventLog

  def record_transaction(account_id, amount) do
    # Record in primary event log
    with :ok <- 
           EventLog.append(account_id, 
             %MyApp.Events.FundsDeposited{amount: amount}),
         
         # Also record in audit log
         :ok <- 
           EventLog.append(account_id, 
             %MyApp.Events.AuditFundsDeposited{amount: amount, timestamp: DateTime.utc_now()},
             event_sequence_id: "audit-log") do
      :ok
    end
  end

  def get_audit_trail(account_id) do
    EventLog.get_for_event_source(account_id, 
      event_sequence_id: "audit-log"
    )
  end
end
```

### Example: Multiple Sequences Per Entity

```elixir
defmodule MyApp.EventSequences do
  @domain_events "domain-events"
  @audit_log "audit-log"
  @external_events "external-events"

  def append_domain_event(entity_id, event) do
    Chronicle.append(entity_id, event, event_sequence_id: @domain_events)
  end

  def append_audit_event(entity_id, event) do
    Chronicle.append(entity_id, event, event_sequence_id: @audit_log)
  end

  def append_external_event(entity_id, event) do
    Chronicle.append(entity_id, event, event_sequence_id: @external_events)
  end

  def get_domain_events(entity_id) do
    Chronicle.EventLog.get_for_event_source(entity_id, 
      event_sequence_id: @domain_events)
  end

  def get_audit_trail(entity_id) do
    Chronicle.EventLog.get_for_event_source(entity_id, 
      event_sequence_id: @audit_log)
  end
end
```

## See Also

- `Chronicle.EventLog` — append and query events
- `Chronicle` — high-level API with convenience functions
- `README.md` — quick start guide
- `CONTEXT.md` — correlation, identity, and causation context
