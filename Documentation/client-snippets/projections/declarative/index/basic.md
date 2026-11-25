```elixir
defmodule MyApp.Events.DecIndexUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "dec-index-user-registered"

  defstruct [:name, :email, :registered_at]
end

defmodule MyApp.ReadModels.DecIndexUserProfile do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :registered_at]
end

defmodule MyApp.Projections.DecIndexUserProfileProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecIndexUserProfile

  alias MyApp.Events.DecIndexUserRegistered

  from DecIndexUserRegistered
end
```
