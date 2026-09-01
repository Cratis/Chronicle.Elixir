```elixir
defmodule MyApp.ReadModels.WatchingBasicOrder do
  defstruct [:id, :status]
end

defmodule MyApp.WatchingReadModelsBasicMonitor do
  alias MyApp.ReadModels.WatchingBasicOrder

  def start_watching do
    {:ok, watcher} = Chronicle.ReadModels.watch(WatchingBasicOrder)
    watcher
  end

  def handle_next_change do
    receive do
      {:chronicle_read_model_changed, WatchingBasicOrder, changeset} ->
        if changeset.removed or is_nil(changeset.read_model) do
          :ok
        else
          IO.puts("#{changeset.model_key}: #{changeset.read_model.status}")
        end
    end
  end

  def stop_watching(watcher), do: Chronicle.ReadModels.unwatch(watcher)
end
```
