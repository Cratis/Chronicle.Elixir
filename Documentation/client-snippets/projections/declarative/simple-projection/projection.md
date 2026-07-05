```elixir
defmodule MyApp.Projections.DecSimpleUserProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecSimpleUser

  alias MyApp.Events.DecSimpleUserCreated

  from DecSimpleUserCreated
end
```
