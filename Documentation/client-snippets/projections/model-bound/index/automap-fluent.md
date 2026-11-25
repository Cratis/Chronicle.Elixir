```elixir
defmodule MyApp.Events.IndexAutoMapAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "index-automap-account-opened-v1"

  defstruct [:name, :balance]
end

defmodule MyApp.ReadModels.IndexAutoMapAccountInfo do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, balance: 0]
end

defmodule MyApp.Projections.IndexAutoMapAccountProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.IndexAutoMapAccountInfo

  alias MyApp.Events.IndexAutoMapAccountOpened

  # No `set:` list — matching properties are mapped automatically.
  from IndexAutoMapAccountOpened
end
```
