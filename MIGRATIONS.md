# Chronicle.Elixir Event Migrations

Chronicle.Elixir supports event type migrations for evolving event schemas across generations while keeping the same event type identifier.

## Overview

A migration connects two adjacent generations of the same event type:

- the `from` event type describes the older generation
- the `to` event type describes the newer generation
- both event types must use the same Chronicle event type id
- the `to` generation must be exactly one higher than the `from` generation

Chronicle registers migrations together with event type schemas. When Chronicle replays or projects historical events, the kernel can use the registered migration chain to move between generations.

## Defining event generations

```elixir
defmodule MyApp.Events.AccountOpenedV1 do
  use Chronicle.EventType, id: "account-opened", generation: 1

  defstruct [:account_id, :owner_name, :initial_balance]
end

defmodule MyApp.Events.AccountOpened do
  use Chronicle.EventType, id: "account-opened", generation: 2

  defstruct [:account_id, :full_name, :initial_balance, :account_tier]
end
```

## Defining a migration

```elixir
defmodule MyApp.Migrations.AccountOpenedV2Migration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.AccountOpenedV1, generation: 1},
    to: {MyApp.Events.AccountOpened, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:owner_name, :full_name)
    |> MigrationBuilder.default_value(:account_tier, "standard")
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:full_name, :owner_name)
  end
end
```

`use Chronicle.Events.Migration` generates `__chronicle_migration__/1` for introspection and validates the migration definition at compile time.

## MigrationBuilder API

`Chronicle.Events.MigrationBuilder` produces the JSON expressions Chronicle expects for migration registration.

### Create a builder

```elixir
builder = Chronicle.Events.MigrationBuilder.new()
```

### Available operations

- `rename_property(builder, source, target)`
- `renamed_from(builder, target, source)`
- `default_value(builder, target, value)`
- `set_property(builder, target, value)`
- `split_property(builder, source, target, separator, part)`
- `combine_properties(builder, sources, target, separator)`
- `copy_property(builder, property)`
- `copy_property(builder, source, target)`
- `to_map(builder)`
- `to_json(builder)`

### Notes

- Property names can be atoms or strings.
- Atom property names are converted from `snake_case` to Chronicle's `camelCase` wire format.
- Unspecified properties are preserved by Chronicle, so `copy_property/2` is a no-op helper for readable pipelines.

## Registering migrations

### Explicit registration

```elixir
children = [
  {Chronicle.Client,
   connection_string: "chronicle://localhost:35000?disableTls=true",
   event_store: "bank",
   event_types: [MyApp.Events.AccountOpenedV1, MyApp.Events.AccountOpened],
   migrations: [MyApp.Migrations.AccountOpenedV2Migration]}
]
```

### Auto-discovery

If your application uses Chronicle macros and starts `Chronicle.Client` with `otp_app: :my_app`, Chronicle discovers migrations automatically through `Chronicle.Artifacts`.

```elixir
children = [
  {Chronicle.Client,
   connection_string: "chronicle://localhost:35000?disableTls=true",
   event_store: "bank",
   otp_app: :my_app}
]
```

## What Chronicle registers

When `Chronicle.Client` starts, it now registers:

- the latest event type definition
- known schemas for all discovered generations
- placeholder schemas for generations referenced only by migrations
- upcast and downcast JMESPath definitions for each migration

This mirrors the Chronicle .NET and TypeScript clients.

## Managing migrations programmatically

`Chronicle.Events.Migrators` groups discovered migration modules by event type id and materializes their registration payloads.

Useful functions:

- `Chronicle.Events.Migrators.new/1`
- `Chronicle.Events.Migrators.all/1`
- `Chronicle.Events.Migrators.for_event_type/2`
- `Chronicle.Events.Migrators.generations_for/2`
- `Chronicle.Events.Migrators.definition_for/1`

## Validation rules

Chronicle.Elixir raises at compile time when:

- the migration skips generations (`InvalidMigrationGenerationGap`)
- either side is not a Chronicle event type
- the `from` and `to` event types use different event type ids

## Sample

See `Samples/console` for a complete working example. The sample appends a legacy `LegacyAccountOpened` generation 1 event and registers a migration to the generation 2 `AccountOpened` event.
