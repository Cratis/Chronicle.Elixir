```elixir
defmodule MyApp.Events.EvtSeedingFeatureUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-feature-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Events.EvtSeedingFeatureOrderPlaced do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-feature-order-placed"

  defstruct [:user_id, :amount]
end

defmodule MyApp.Seeders.EvtSeedingUserFeatureSeeding do
  use Cratis.Chronicle.Seeding.Seeder

  alias MyApp.Events.EvtSeedingFeatureUserRegistered

  @impl true
  def seed(builder) do
    Cratis.Chronicle.Seeding.for(builder, EvtSeedingFeatureUserRegistered, "test-user-1", [
      %EvtSeedingFeatureUserRegistered{email: "test1@example.com", display_name: "Test User 1"}
    ])
  end
end

defmodule MyApp.Seeders.EvtSeedingOrderFeatureSeeding do
  use Cratis.Chronicle.Seeding.Seeder

  alias MyApp.Events.EvtSeedingFeatureOrderPlaced

  @impl true
  def seed(builder) do
    Cratis.Chronicle.Seeding.for(builder, EvtSeedingFeatureOrderPlaced, "test-order-1", [
      %EvtSeedingFeatureOrderPlaced{user_id: "test-user-1", amount: 100.00}
    ])
  end
end
```
