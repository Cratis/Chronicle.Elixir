```elixir
defmodule MyApp.ReadModels.WatchingFilteringOrder do
  defstruct [:id, :total_amount]
end

defmodule MyApp.WatchingReadModelsFilteringMonitor do
  alias MyApp.ReadModels.WatchingFilteringOrder

  def start_watching do
    {:ok, watcher} = Chronicle.ReadModels.watch(WatchingFilteringOrder)
    watcher
  end

  def handle_next_change(threshold) do
    # Filtering happens client-side, in the process receiving the changes.
    receive do
      {:chronicle_read_model_changed, WatchingFilteringOrder, changeset} ->
        if changeset.read_model && changeset.read_model.total_amount > threshold do
          IO.puts("#{changeset.model_key}: #{changeset.read_model.total_amount}")
        end
    end
  end
end
```
