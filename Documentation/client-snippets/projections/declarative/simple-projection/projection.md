```elixir
defmodule MyApp.Projections.DecSimpleUserProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecSimpleUser

  alias MyApp.Events.DecSimpleUserCreated

  from DecSimpleUserCreated
end
```
