```elixir
defmodule MyApp.MaterializedPaginationOrdersController do
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def get_orders(page \\ 0, page_size \\ 20) do
    with {:ok, result} <-
           Chronicle.ReadModels.query(MaterializedPaginationOrder,
             page: page,
             page_size: page_size
           ) do
      {:ok, result.instances}
    end
  end
end
```
