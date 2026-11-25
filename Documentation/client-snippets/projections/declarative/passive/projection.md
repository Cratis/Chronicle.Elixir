```elixir title="Passive projection"
defmodule MyApp.Projections.DecPassiveUserSummaryProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecPassiveUserSummary, passive: true

  alias MyApp.Events.{DecPassiveUserCreated, DecPassiveUserUpdated}

  from DecPassiveUserCreated
  from DecPassiveUserUpdated
end
```
