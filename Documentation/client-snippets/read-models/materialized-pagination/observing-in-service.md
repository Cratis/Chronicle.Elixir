```elixir
defmodule MyApp.MaterializedPaginationProductDashboard do
  use GenServer

  alias Chronicle.ReadModels
  alias MyApp.ReadModels.MaterializedPaginationOrder

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    case ReadModels.observe(MaterializedPaginationOrder, page: 0, page_size: 100) do
      {:ok, observer} -> {:ok, %{observer: observer, orders: []}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_info({:chronicle_read_model_instances, MaterializedPaginationOrder, page}, state) do
    # Update the dashboard on the initial page and every subsequent snapshot.
    {:noreply, %{state | orders: page.instances}}
  end

  def handle_info({:chronicle_read_model_observe_error, MaterializedPaginationOrder, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(_reason, state), do: ReadModels.unobserve(state.observer)
end
```
