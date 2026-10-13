---
sharedTopicBridge: true
---

# Constraints

Constraints are shared Chronicle behavior. The shared docs cover constraint concepts, model-bound constraints, declarative constraints, and client-tabbed examples.

- [Constraints](/chronicle/constraints/)
- [Understanding constraints](/chronicle/understanding-constraints/)
- [Elixir client setup](./get-started.md)

## Scoping uniqueness checks

`unique/2` accepts a `:scope` option that narrows a uniqueness check to values observed at
append time along one or more dimensions, instead of checking globally across the whole
event store. Mirrors the C# client's `IConstraintBuilder.PerEventSourceType()` /
`PerEventStreamType()` / `PerEventStreamId()`.

`:scope` takes an atom — `:per_event_source_type`, `:per_event_stream_type`, or
`:per_event_stream_id` — or a list of them to scope along more than one dimension at once:

```elixir
defmodule MyApp.Events.EmailChanged do
  use Chronicle.Events.EventType, id: "email-changed"

  defstruct [:email]

  # Unique only among events from the same event source type — the same email value
  # may repeat across different event source types (e.g. an employee and a customer
  # can share an email without tripping this constraint).
  unique(:email, scope: :per_event_source_type)
end
```

Without `:scope`, uniqueness is checked globally, as before.

## Unique modes

`unique :code, mode: :per_value` keeps every value until a removal event releases it. The default,
`mode: :per_event_source`, keeps one value per event source and frees the previous one when it is
replaced.

## Closing events

An event that ends something declares `closes_stream`. Appending it closes its stream scope; every
later event inside that scope is refused, events elsewhere are not. Mirrors .NET's `[ClosesStream]`:

```elixir
defmodule MyApp.Events.PeriodClosed do
  use Chronicle.Events.EventType, id: "period-closed"
  defstruct period: ""

  closes_stream event_stream_id_from: :period, reopened_by: [MyApp.Events.PeriodReopened]
end
```

Options: `:dimensions` (`:event_source_id`, `:event_source_type`, `:event_stream_type`,
`:event_stream_id`), `:event_stream_id_from` (the event field that names the stream), `:reopened_by`
(event types that lift the closure of exactly that scope), `:name` and `:event_sequences`.
Declarations that share a `:name` merge, and must agree on dimensions and stream id field. A
registration closes nothing in history; only later appends close scopes. Inspect and operate on
closed scopes with `Chronicle.EventSequences.Streams`.
