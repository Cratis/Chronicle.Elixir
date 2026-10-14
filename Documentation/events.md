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

`public:` makes the event type visible to other event stores through event store subscriptions;
it does not change who can append to or read from this event store directly.

## A previous generation: `generation_for:`

A module that represents an **older** generation of an existing event type declares
`generation_for:` instead of its own `:id`. The event type id is resolved from the target module,
so the two generations can never drift apart by a hand-typed, mismatched id string:

```elixir
defmodule MyApp.Events.CustomerRegistered do
  use Chronicle.Events.EventType, id: "customer-registered", generation: 2
  defstruct customer_id: "", full_name: ""
end

defmodule MyApp.Events.CustomerRegisteredV1 do
  use Chronicle.Events.EventType, generation_for: MyApp.Events.CustomerRegistered, generation: 1
  defstruct customer_id: "", owner_name: ""
end
```

`generation_for:` requires an explicit `generation:` (the generation this module represents) and
cannot be combined with `:id` - a module is either the current event type or a previous generation
of one, not both. See [Migrations](./migrations.md) for bridging generations with an
`Chronicle.Events.Migration`.

## Validation errors

A few event type and migration mistakes are checked before the client connects. The client logs
the full error and continues by default; set `strict_validation: true` on `Chronicle.Client` to
raise instead, so a bad set fails immediately rather than being retried by the registration
coordinator. `Chronicle.Events.EventTypes.validate/2` returns `:ok | {:error, exception}` and
`validate!/2` raises:

- `Chronicle.Events.MultipleEventTypesWithSameIdFound` - two modules represent the same
  generation of the same event type id. Each generation must be represented by exactly one
  module.
- `Chronicle.Events.MultipleMigratorsForSameEventTypeGeneration` - more than one
  `Chronicle.Events.Migration` module bridges the same pair of generations for an event type.
  Exactly one migrator may bridge a pair of generations.
- `ArgumentError` - a migration's `:from` and `:to`
  resolve to different event type ids. Mark the previous generation with `generation_for:`
  instead of giving it a separate `:id`.
- `Chronicle.Events.EventTypeGenerationForCannotBeCombinedWithEventType` - a module gives both
  `:id` and `:generation_for`.
- `Chronicle.Events.EventTypeGenerationReferencesNonEventType` - `generation_for:` names a module
  that doesn't `use Chronicle.Events.EventType`.

## Maps and nested structs

Event payloads are written with camelCase field names at every depth, and the schema is generated
the same way, so a nested struct's `series_name` arrives as `seriesName`. A plain map field
(`parameters: %{}`) is an object whose keys are *data* and are never transformed. Declare
fields that default to `nil` or hold lists of structs with `types:`. See `Chronicle.Serialization`.
