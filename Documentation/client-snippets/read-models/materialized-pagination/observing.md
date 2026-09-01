```elixir
defmodule MyApp.MaterializedPaginationObserving do
  alias Chronicle.ReadModels
  alias MyApp.ReadModels.MaterializedPaginationOrder

  # Elixir has no single "ObserveInstances" call — combine watch/2
  # (per-instance change notifications) with query/2 (the current
  # materialized page) to get the same "re-emit the page whenever the
  # stored data changes" behavior as ObserveInstances(take: 50).
  def run do
    {:ok, watcher} = ReadModels.watch(MaterializedPaginationOrder)

    receive do
      {:chronicle_read_model_changed, MaterializedPaginationOrder, _changeset} ->
        {:ok, page} = ReadModels.query(MaterializedPaginationOrder, page: 1, page_size: 50)
        IO.puts("Orders updated: #{length(page.instances)} in view")
    after
      5_000 -> :timeout
    end

    # Stop watching once done, to release the change stream.
    ReadModels.unwatch(watcher)
  end
end
```
