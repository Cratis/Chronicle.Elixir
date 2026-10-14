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

## Unique constraint options

`unique/2` and `unique_event_type/1` (model-bound, declared as an event type attribute) and
`unique/2`/`unique_event_type/1,2` (standalone, see below) share the same option set:

| Option | Applies to | Meaning |
|---|---|---|
| `:name` | both | the constraint name; required on a standalone declaration, defaults to the first field (`unique/2`) or the event type id (`unique_event_type/1`) on a model-bound one |
| `:mode` | `unique/2` only | `:per_event_source` (default) or `:per_value` — see *Unique modes* below |
| `:ignore_casing` | `unique/2` only | compare values case-insensitively |
| `:message` | both | a string, or a `{Module, :function}` callback — see *Violation messages* below |
| `:scope` | both | narrows uniqueness checking to values observed at append time along one or more dimensions (`:per_event_source_type`, `:per_event_stream_type`, `:per_event_stream_id`), mirroring the C# client's `IConstraintBuilder.PerEventSourceType()`/`PerEventStreamType()`/`PerEventStreamId()`. Defaults to unscoped (checked globally) |
| `:event_sequences` | both | restrict the declaration to specific event sequences (default: all) |

An unknown option, an invalid `:mode`, or an invalid `:scope` value emits a compile warning naming the module and the option. The declaration still compiles: an unknown `:mode` raises `ArgumentError` when the constraint definition is built, and an unknown option or invalid `:scope` is ignored, as in earlier releases.

## Unique modes

`unique :code, mode: :per_value` keeps every value until a removal event releases it. The default,
`mode: :per_event_source`, keeps one value per event source and frees the previous one when it is
replaced.

## Releasing a held value

In `:per_value` mode, `remove_constraint/1` releases every value a removal event's event source
held. `remove_constraint/2` with `:properties` releases only the value the removal event itself
carries, in the same order as the constrained properties:

```elixir
defmodule MyApp.Events.MappingVersionRegistered do
  use Chronicle.Events.EventType, id: "mapping-version-registered"
  defstruct version_id: ""

  unique(:version_id, name: "UniqueMappingVersionId", mode: :per_value)
end

defmodule MyApp.Events.MappingVersionRemoved do
  use Chronicle.Events.EventType, id: "mapping-version-removed"
  defstruct version_id: ""

  remove_constraint("UniqueMappingVersionId", properties: [:version_id])
end
```

## Standalone constraint modules

`unique/2` and `unique_event_type/1` declared as event type attributes cover a constraint that
belongs to exactly one event type's own module. `use Chronicle.Events.Constraint` is for a
constraint spanning several event types under one name, or one defined apart from any single
event type's module — mirroring the C# client's `IConstraint`/`IConstraintBuilder`:

```elixir
defmodule MyApp.Constraints.UniqueEmail do
  use Chronicle.Events.Constraint

  unique name: "UniqueEmail" do
    on MyApp.Events.UserRegistered, [:email]
    on MyApp.Events.UserEmailChanged, [:new_email]
    removed_with MyApp.Events.UserRemoved
  end
end
```

`on/2` declares one of the participating event types and its properties; call it more than once
to constrain several event types under one name. `removed_with/1,2` inside a `unique/2` block
releases the value, optionally with `properties:` (as above, in `:per_value` mode); after a bare
`unique_event_type/1,2` it releases that constraint instead — calling it before any
`unique_event_type/1,2` has been declared in the module is a compile-time error. Two
`unique_event_type/1,2` declarations sharing a `:name` merge into one mutually-exclusive
constraint — at most one event drawn from the named set is ever appended for the same event
source:

```elixir
defmodule MyApp.Constraints.PersonTerminalOutcome do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.PersonAliasedTo, name: "PersonTerminal"
  unique_event_type MyApp.Events.PersonErased, name: "PersonTerminal"
end
```

Standalone constraint modules are discovered automatically (like event types and read models) or
registered explicitly with the `:constraints` client option:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  constraints: [MyApp.Constraints.UniqueEmail]}
```

## Violation messages and details

`:message` accepts a string or a `{Module, :function}` callback, invoked with the violation when
an append is rejected. The violation's `:details` carry the keys Chronicle itself assigns a
meaning to; `Chronicle.Events.ConstraintViolation.details/1` maps them onto atoms —
`:property_name`, `:property_value`, `:closed_by`, `:closed_at_sequence_number` — leaving any other
key as-is:

```elixir
defmodule MyApp.Constraints.Messages do
  alias Chronicle.Events.ConstraintViolation

  def project_name_taken(violation) do
    "A project named '#{ConstraintViolation.details(violation)[:property_value]}' already exists."
  end
end

defmodule MyApp.Events.ProjectCreated do
  use Chronicle.Events.EventType, id: "project-created"
  defstruct name: ""

  unique(:name, name: "UniqueProjectName", message: {MyApp.Constraints.Messages, :project_name_taken})
end
```

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
