```elixir
defmodule MyApp.Events.EvtSeedingCorrectionUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-correction-user-registered"

  defstruct email: "", display_name: ""
end

defmodule MyApp.Seeders.EvtSeedingCorrection do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.EvtSeedingCorrectionUserRegistered

  @impl true
  def seed(builder) do
    Chronicle.Seeding.for(builder, EvtSeedingCorrectionUserRegistered, "user-123", [
      %EvtSeedingCorrectionUserRegistered{email: "john@example.com", display_name: "John Doe"}
    ])
  end
end
```
