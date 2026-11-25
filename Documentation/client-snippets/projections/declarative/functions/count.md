```elixir title="Count function"
defmodule MyApp.Events.DecFunctionsUserLoggedIn do
  use Cratis.Chronicle.Events.EventType, id: "dec-functions-user-logged-in"

  defstruct [:username]
end

defmodule MyApp.Events.DecFunctionsUserPerformedAction do
  use Cratis.Chronicle.Events.EventType, id: "dec-functions-user-performed-action"

  defstruct [:username, :action_type]
end

defmodule MyApp.ReadModels.DecFunctionsUserActivity do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:username, login_count: 0, action_count: 0]
end

defmodule MyApp.Projections.DecFunctionsUserActivityProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecFunctionsUserActivity

  alias MyApp.Events.{DecFunctionsUserLoggedIn, DecFunctionsUserPerformedAction}

  from DecFunctionsUserLoggedIn,
    count: :login_count

  from DecFunctionsUserPerformedAction,
    count: :action_count
end
```
