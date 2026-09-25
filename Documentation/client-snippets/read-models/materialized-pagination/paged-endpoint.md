```elixir
defmodule MyApp.MaterializedPaginationOrdersController do
  alias MyApp.ReadModels.MaterializedPaginationOrder

  # HTTP page indexes begin at 0; Chronicle query pages begin at 1.
  def get_orders(page \\ 0, page_size \\ 20) do
    with {:ok, result} <-
           Chronicle.ReadModels.query(MaterializedPaginationOrder,
             page: page + 1,
             page_size: page_size
           ) do
      {:ok, result.instances}
    end
  end
end
```
