```elixir
defmodule MyApp.MaterializedPaginationBasicUsage do
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def get_orders do
    Cratis.Chronicle.ReadModels.query(MaterializedPaginationOrder)
  end
end
```
