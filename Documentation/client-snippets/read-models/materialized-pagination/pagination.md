```elixir
defmodule MyApp.MaterializedPaginationPagination do
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def get_pages do
    # First page of 20. Pages count from 0.
    {:ok, page1} = Chronicle.ReadModels.query(MaterializedPaginationOrder, page: 0, page_size: 20)
    IO.puts("Page 1: #{length(page1.instances)} orders")

    # Second page of 20
    {:ok, page2} = Chronicle.ReadModels.query(MaterializedPaginationOrder, page: 1, page_size: 20)
    IO.puts("Page 2: #{length(page2.instances)} orders")

    # Third page of 20
    {:ok, page3} = Chronicle.ReadModels.query(MaterializedPaginationOrder, page: 2, page_size: 20)
    IO.puts("Page 3: #{length(page3.instances)} orders")
  end
end
```
