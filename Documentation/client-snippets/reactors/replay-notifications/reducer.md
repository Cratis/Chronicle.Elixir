```elixir
defmodule MyApp.Events.ReplayNotifiedItemAdded do
  use Chronicle.Events.EventType, id: "replay-notified-item-added"

  defstruct [:order_id]
end

defmodule MyApp.ReadModels.ReplayNotifiedOrderTotals do
  defstruct items: 0
end

defmodule MyApp.Reducers.ReplayNotifiedOrderTotalsReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.ReplayNotifiedOrderTotals

  alias MyApp.Events.ReplayNotifiedItemAdded
  alias MyApp.ReadModels.ReplayNotifiedOrderTotals

  @handles ReplayNotifiedItemAdded

  @impl true
  def reduce(%ReplayNotifiedItemAdded{}, current, _context) do
    %ReplayNotifiedOrderTotals{items: (if current, do: current.items, else: 0) + 1}
  end

  @impl true
  def on_replay_begin, do: :ok

  @impl true
  def on_replay_end, do: :ok
end
```
