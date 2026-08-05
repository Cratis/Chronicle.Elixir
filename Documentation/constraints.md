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
