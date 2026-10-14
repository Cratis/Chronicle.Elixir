---
sharedTopicBridge: true
---

# Migrations

Event type migrations are shared Chronicle behavior. The shared docs own the migration model and client-tabbed examples.

- [Understanding event evolution](/chronicle/understanding-event-evolution/)
- [Event type migrations concept](/chronicle/concepts/event-type-migrations/)
- [Migrations](/chronicle/migrations/)
- [Elixir client setup](./get-started.md)

## Declaring a previous generation

A module representing an older generation of an event type can declare `generation_for:` instead
of giving itself a separate `:id`. The id is resolved from the target module, so the two
generations can never drift apart by a hand-typed, mismatched id string - see
[A previous generation: `generation_for:`](./events.md#a-previous-generation-generation_for) on the
Events page.

```elixir
defmodule MyApp.Events.AuthorRegistered do
  use Chronicle.Events.EventType, id: "author-registered", generation: 2
  defstruct [:first_name, :last_name]
end

defmodule MyApp.Events.AuthorRegisteredV1 do
  use Chronicle.Events.EventType, generation_for: MyApp.Events.AuthorRegistered, generation: 1
  defstruct [:name]
end

defmodule MyApp.Migrations.AuthorRegisteredMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.AuthorRegisteredV1, generation: 1},
    to: {MyApp.Events.AuthorRegistered, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.split_property(:name, :first_name, " ", 0)
    |> MigrationBuilder.split_property(:name, :last_name, " ", 1)
  end

  @impl true
  def downcast(builder) do
    MigrationBuilder.combine_properties(builder, [:first_name, :last_name], :name, " ")
  end
end
```

## Migration checks

A few mistakes are rejected before the client connects, so a bad set fails immediately instead of
being retried:

- Two modules representing the same generation of the same event type id raise
  `Chronicle.Events.MultipleEventTypesWithSameIdFound`.
- More than one migration module bridging the same pair of generations raises
  `Chronicle.Events.MultipleMigratorsForSameEventTypeGeneration` - exactly one migrator may bridge
  a pair of generations.
- A migration whose `:from` and `:to` resolve to different event type ids raises
  `Chronicle.Events.MigrationGenerationsMustShareEventTypeId` - mark the previous generation with
  `generation_for:` instead of giving it a separate `:id`.
- A non-adjacent generation gap (for example `from: generation: 1` to `to: generation: 3`) raises
  `Chronicle.Events.InvalidMigrationGenerationGap`.
