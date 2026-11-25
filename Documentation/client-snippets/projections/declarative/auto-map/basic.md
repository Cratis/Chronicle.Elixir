```elixir title="AutoMap by convention"
defmodule MyApp.Events.AutoMapUserCreated do
  use Cratis.Chronicle.Events.EventType, id: "auto-map-user-created"

  defstruct [:name, :email]
end

defmodule MyApp.Events.AutoMapUserRenamed do
  use Cratis.Chronicle.Events.EventType, id: "auto-map-user-renamed"

  defstruct [:name]
end

defmodule MyApp.ReadModels.AutoMapUser do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, :email]
end

defmodule MyApp.Projections.AutoMapUserProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.AutoMapUser

  alias MyApp.Events.{AutoMapUserCreated, AutoMapUserRenamed}

  from AutoMapUserCreated
  from AutoMapUserRenamed
end
```
