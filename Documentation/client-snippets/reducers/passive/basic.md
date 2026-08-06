```elixir
defmodule MyApp.Reducers.AccountReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.AccountInfo, active: false

  alias MyApp.Events.OrderPlaced

  @handles OrderPlaced

  @impl true
  def reduce(%OrderPlaced{}, model, _context), do: model
end
```
