```elixir
defmodule MyApp.Events.EvtSeedingMultiSameTypeUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-multi-same-type-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Seeders.EvtSeedingMultipleSameTypeSeeding do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.EvtSeedingMultiSameTypeUserRegistered

  @impl true
  def seed(builder) do
    Chronicle.Seeding.for(builder, EvtSeedingMultiSameTypeUserRegistered, "user-123", [
      %EvtSeedingMultiSameTypeUserRegistered{email: "john@example.com", display_name: "John"},
      %EvtSeedingMultiSameTypeUserRegistered{email: "jane@example.com", display_name: "Jane"}
    ])
  end
end
```
