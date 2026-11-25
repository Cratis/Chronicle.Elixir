```elixir
defmodule MyApp.Events.IndexExplicitAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "index-explicit-account-opened-v1"

  defstruct [:name, :initial_balance]
end

defmodule MyApp.ReadModels.IndexExplicitAccountInfo do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, balance: 0]
end

defmodule MyApp.Projections.IndexExplicitAccountProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.IndexExplicitAccountInfo

  alias MyApp.Events.IndexExplicitAccountOpened

  from IndexExplicitAccountOpened,
    set: [name: :name, balance: :initial_balance]
end
```
