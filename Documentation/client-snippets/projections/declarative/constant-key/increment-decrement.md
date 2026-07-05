```elixir title="Increment/decrement with a constant key"
defmodule MyApp.Events.DecConstantKeyUserRegistered do
  use Chronicle.Events.EventType, id: "dec-constant-key-user-registered"

  defstruct [:name]
end

defmodule MyApp.Events.DecConstantKeyUserLoggedIn do
  use Chronicle.Events.EventType, id: "dec-constant-key-user-logged-in"

  defstruct []
end

defmodule MyApp.Events.DecConstantKeyUserLoggedOut do
  use Chronicle.Events.EventType, id: "dec-constant-key-user-logged-out"

  defstruct []
end

defmodule MyApp.ReadModels.DecConstantKeySiteStatistics do
  use Chronicle.ReadModels.ReadModel

  defstruct total_users: 0, active_sessions: 0
end

defmodule MyApp.Projections.DecConstantKeySiteStatisticsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecConstantKeySiteStatistics

  alias MyApp.Events.{DecConstantKeyUserRegistered, DecConstantKeyUserLoggedIn, DecConstantKeyUserLoggedOut}

  from DecConstantKeyUserRegistered,
    key: "site",
    count: :total_users

  from DecConstantKeyUserLoggedIn,
    key: "site",
    add: [active_sessions: 1]

  from DecConstantKeyUserLoggedOut,
    key: "site",
    subtract: [active_sessions: 1]
end
```
