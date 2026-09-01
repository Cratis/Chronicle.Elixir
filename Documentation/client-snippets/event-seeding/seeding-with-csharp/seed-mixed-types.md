```elixir
defmodule MyApp.Events.EvtSeedingMixedTypesUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-mixed-types-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Events.EvtSeedingMixedTypesEmailVerified do
  use Chronicle.Events.EventType, id: "evt-seeding-mixed-types-email-verified"

  defstruct [:email]
end

defmodule MyApp.Events.EvtSeedingMixedTypesProfileUpdated do
  use Chronicle.Events.EventType, id: "evt-seeding-mixed-types-profile-updated"

  defstruct [:display_name]
end

defmodule MyApp.Seeders.EvtSeedingMixedTypesSeeding do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.{
    EvtSeedingMixedTypesEmailVerified,
    EvtSeedingMixedTypesProfileUpdated,
    EvtSeedingMixedTypesUserRegistered
  }

  @impl true
  def seed(builder) do
    Chronicle.Seeding.for_event_source(builder, "user-123", [
      %EvtSeedingMixedTypesUserRegistered{email: "john@example.com", display_name: "John"},
      %EvtSeedingMixedTypesEmailVerified{email: "john@example.com"},
      %EvtSeedingMixedTypesProfileUpdated{display_name: "John Doe"}
    ])
  end
end
```
