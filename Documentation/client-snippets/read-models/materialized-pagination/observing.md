```elixir
defmodule MyApp.MaterializedPaginationObserving do
  alias Chronicle.ReadModels
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def run do
    {:ok, observer} = ReadModels.observe(MaterializedPaginationOrder, page: 0, page_size: 50)

    try do
      receive_pages()
    after
      ReadModels.unobserve(observer)
    end
  end

  defp receive_pages do
    receive do
      {:chronicle_read_model_instances, MaterializedPaginationOrder, page} ->
        # Receives the initial stored page and each updated page.
        IO.puts("Orders updated: #{length(page.instances)} in view")
        receive_pages()

      {:chronicle_read_model_observe_error, MaterializedPaginationOrder, reason} ->
        {:error, reason}

      :stop ->
        :ok
    end
  end
end
```
