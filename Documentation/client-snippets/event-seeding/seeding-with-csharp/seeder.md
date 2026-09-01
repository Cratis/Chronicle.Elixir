```elixir
defmodule MyApp.Events.EvtSeedingSeederUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-seeder-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Events.EvtSeedingSeederEmailVerified do
  use Chronicle.Events.EventType, id: "evt-seeding-seeder-email-verified"

  defstruct [:email]
end

defmodule MyApp.Seeders.EvtSeedingUserSeeding do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.{EvtSeedingSeederEmailVerified, EvtSeedingSeederUserRegistered}

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(EvtSeedingSeederUserRegistered, "user-123", [
      %EvtSeedingSeederUserRegistered{email: "john@example.com", display_name: "John"}
    ])
    |> Chronicle.Seeding.for_event_source("user-456", [
      %EvtSeedingSeederUserRegistered{email: "jane@example.com", display_name: "Jane"},
      %EvtSeedingSeederEmailVerified{email: "jane@example.com"}
    ])
  end
end
```
