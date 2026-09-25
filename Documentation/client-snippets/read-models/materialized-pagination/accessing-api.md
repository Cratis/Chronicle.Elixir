```elixir
defmodule MyApp.ReadModels.MaterializedPaginationOrder do
  use Chronicle.ReadModels.ReadModel

  defstruct customer_name: "", total: 0.0
end

defmodule MyApp.MaterializedPaginationAccessingApi do
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def get_orders do
    # Query the materialized read-model container directly, rather than replaying events
    Chronicle.ReadModels.query(MaterializedPaginationOrder)
  end
end
```
