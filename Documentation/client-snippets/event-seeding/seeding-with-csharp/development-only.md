```elixir
defmodule MyApp.Events.EvtSeedingDevUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-dev-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Seeders.EvtSeedingDevelopmentSeeding do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.EvtSeedingDevUserRegistered

  @impl true
  def seed(builder) do
    Chronicle.Seeding.for(builder, EvtSeedingDevUserRegistered, "dev-user-1", [
      %EvtSeedingDevUserRegistered{email: "dev@example.com", display_name: "Dev User"}
    ])
  end
end

defmodule MyApp.EvtSeedingApplication do
  use Application

  # Chronicle doesn't distinguish between development and production seed
  # data — decide when to seed based on build configuration or runtime
  # settings, resolved once at compile time here via Mix.env/0.
  @dev_seeders (if Mix.env() == :dev do
                  [MyApp.Seeders.EvtSeedingDevelopmentSeeding]
                else
                  []
                end)

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: "chronicle://localhost:35000",
       event_store: "my-store",
       seeders: @dev_seeders}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
