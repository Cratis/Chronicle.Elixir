```elixir
defmodule ReducersSyncSignaturesMetricRecorded do
  use Chronicle.Events.EventType, id: "reducers-sync-signatures-metric-recorded"

  defstruct [:value]
end

defmodule ReducersSyncSignaturesStats do
  defstruct total: 0
end

defmodule ReducersSyncSignaturesReducer do
  use Chronicle.Reducers.Reducer, model: ReducersSyncSignaturesStats

  alias ReducersSyncSignaturesMetricRecorded

  @handles ReducersSyncSignaturesMetricRecorded

  # Every reducer has this one shape: the event, the current state, then the
  # context map — there is no family of overloads to choose between.
  @impl true
  def reduce(%ReducersSyncSignaturesMetricRecorded{} = event, current, _context) do
    total = if current, do: current.total, else: 0
    %ReducersSyncSignaturesStats{total: total + event.value}
  end
end
```
