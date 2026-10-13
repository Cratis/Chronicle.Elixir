---
sharedTopicBridge: true
---

# Events

Events and event logs are shared Chronicle topics. Use the shared docs for event modeling, event types, appending, querying, and evolution.

- [Events and event logs](/chronicle/events/)
- [Event concept](/chronicle/concepts/event/)
- [Appending events](/chronicle/events/appending/)
- [Event evolution](/chronicle/understanding-event-evolution/)
- [Elixir client setup](./get-started.md)

## Event type options

```elixir
use Chronicle.Events.EventType,
  id: "customer-registered",
  generation: 1,
  subject: :customer_id,        # the field naming the data subject (see below)
  tags: ["billing"],            # tags every append of this event carries
  tombstone: true,              # the last event of an event source's life
  public: true,                 # visible to other event stores' subscriptions
  compensation_for: MyApp.Events.CustomerRegisteredInError,
  types: [addresses: {:list, MyApp.Address}]
```

`subject:` resolves the data subject of an append from the event itself, so the right erasure key
protects the PII even when the person is not the event source. An explicit `subject:` option on the
append wins; without either, the kernel uses the event source id. `tombstone`, `public` and
`compensation_for` mirror .NET's `[Tombstone]`, `[Public]` and `[CompensationFor<T>]`.

## Maps and nested structs

Event payloads are written with camelCase field names at every depth, and the schema is generated
the same way, so a nested struct's `series_name` arrives as `seriesName`. A plain map field
(`parameters: %{}`) is an object whose keys are *data* and are never transformed. Declare
fields that default to `nil` or hold lists of structs with `types:`. See `Chronicle.Serialization`.
