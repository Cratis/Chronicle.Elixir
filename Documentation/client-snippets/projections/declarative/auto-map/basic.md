```elixir title="AutoMap by convention"
defmodule MyApp.Events.AutoMapUserCreated do
  use Chronicle.Events.EventType, id: "auto-map-user-created"

  defstruct [:name, :email]
end

defmodule MyApp.Events.AutoMapUserRenamed do
  use Chronicle.Events.EventType, id: "auto-map-user-renamed"

  defstruct [:name]
end

defmodule MyApp.ReadModels.AutoMapUser do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email]
end

defmodule MyApp.Projections.AutoMapUserProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AutoMapUser

  alias MyApp.Events.{AutoMapUserCreated, AutoMapUserRenamed}

  from AutoMapUserCreated
  from AutoMapUserRenamed
end
```
