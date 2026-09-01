# Concepts

A `String.t()` is a `String.t()` is a `String.t()`. Nothing stops an employee id
being passed where a customer id was expected, or a plain email address
sitting in an event field with no signal at all that it needs to be
encrypted. Both compile. Both look fine in code review. The bug — or the
compliance gap — surfaces later, in production.

`Chronicle.Concept` gives a domain value a type of its own: a small wrapper
struct that declares what the value *is*, and, when it matters, that it is
personally identifiable information Chronicle should protect.

## Declaring one

Use `Chronicle.Concept` in a module and declare the primitive type it wraps:

```elixir
defmodule MyApp.PersonName do
  use Chronicle.Concept, type: :string
end

defmodule MyApp.Age do
  use Chronicle.Concept, type: :integer
end
```

Supported types are `:string`, `:integer`, `:float`, `:boolean`, and `:uuid`.
Anything else raises `ArgumentError` at compile time, with the list of valid
types in the message.

A concept is a plain struct with a single field:

```elixir
%MyApp.PersonName{value: "Ada Lovelace"}
```

Use it wherever a raw value used to sit, as the **default value** of a
`defstruct` field on an event type or read model:

```elixir
defmodule MyApp.Events.EmployeeRegistered do
  use Chronicle.Events.EventType, id: "employee-registered"

  defstruct name: %MyApp.PersonName{}, department: ""
end
```

The default matters, not just as a starting value: `Chronicle.Schemas.JsonSchemaGenerator`
reads struct field defaults to build the JSON schema Chronicle registers, so
a field's default is also how the generator learns the field's type. A field
that should be recognized as a `MyApp.PersonName` needs `%MyApp.PersonName{}`
as its default — `nil` carries no type information to infer from.

## What goes on the wire

A concept serializes as the value it wraps, not as an object wrapping one:

```elixir
iex> Jason.encode!(%MyApp.PersonName{value: "Ada Lovelace"})
"\"Ada Lovelace\""
```

That is what makes a concept something you can adopt for a property that is
already in production. The JSON does not change, the schema Chronicle
validates against does not change, and every event stored before the concept
existed still reads back. This mirrors the intent of Kotlin's `ConceptAs<T>`
and its `ConceptTypeAdapterFactory`, and C#'s `ConceptAs<T>`.

## Concepts and compliance (PII)

The most useful thing a concept does is carry its compliance classification
with it. Declare `pii/0,1` once, on the concept, and every event or read
model field that uses it is encrypted automatically — no need to remember
`Chronicle.Compliance.pii/1,2` on every event that happens to carry the
value:

```elixir
defmodule MyApp.PersonName do
  use Chronicle.Concept, type: :string
  pii("Legal name of the data subject")
end
```

The optional `details` argument documents *why* the value is classified as
PII — the legal basis or retention period, for example. It is stored in the
generated schema for compliance tooling to read; it plays no part in
encryption.

`Chronicle.Schemas.JsonSchemaGenerator` resolves PII from two places, and
applies both consistently across event type registration and read model
registration:

* **Property-level** — `pii(:field, details)` declared on the event type or
  read model module itself, exactly as before.
* **Type-level** — a field whose default value is an instance of a
  `Chronicle.Concept` module that declared `pii/0,1` on itself.

The generator also **descends into nested structs**, so a concept does not
have to sit directly on an event or read model field — it is still found
several levels down, inside a plain value object:

```elixir
defmodule MyApp.Address do
  defstruct street: %MyApp.PersonName{}, postal_code: ""
end
```

and inside a **list**, where the first element's schema (including its
compliance metadata) becomes the schema for every item:

```elixir
defmodule MyApp.Events.EmployeeRegistered do
  use Chronicle.Events.EventType, id: "employee-registered-with-aliases"

  defstruct name: %MyApp.PersonName{}, aliases: [%MyApp.PersonName{}]
end
```

Compliance metadata always ends up on a schema **leaf** — never on a
container node describing a whole object — with one deliberate exception:
compliance declared on the array *field itself* (rather than resolved from
its element type) stays on the array, because Chronicle blob-encrypts that
collection as a whole. A leaf reached through more than one path (a
concept's own PII plus a redundant property-level `pii/1,2` on the same
field) is only ever recorded once.

## Event source ids are never PII

A concept can also stand in for a Chronicle event source identifier:

```elixir
defmodule MyApp.EmployeeId do
  use Chronicle.Concept, type: :uuid, event_source_id: true
end
```

Chronicle uses the event source id to look up the encryption key for a
subject's PII values, so it cannot itself be one of the encrypted values —
you cannot use the key to find the key. Combining `event_source_id: true`
with `pii/0,1` on the same concept raises `ArgumentError` at compile time,
mirroring the C# client's `PIINotSupportedOnEventSourceId`:

```elixir
defmodule MyApp.EmployeeId do
  use Chronicle.Concept, type: :uuid, event_source_id: true
  # Raises ArgumentError at compile time.
  pii()
end
```

If the identifier itself is sensitive, use a non-sensitive surrogate (a
random `:uuid` concept with `event_source_id: true` and no `pii`) as the
event source id, and store the sensitive value in a separate PII-marked
concept.

## Introspection

`__chronicle_concept__/1` exposes a concept's metadata, accepting `:type`,
`:event_source_id?`, or `:pii` as the key:

```elixir
MyApp.PersonName.__chronicle_concept__(:type)
#=> :string

MyApp.PersonName.__chronicle_concept__(:event_source_id?)
#=> false
```

See [Compliance](compliance.md) for the full PII picture, including
right-to-erasure key deletion.
