```elixir
defmodule PassiveReducersDataRecorded do
  use Chronicle.Events.EventType, id: "passive-reducers-data-recorded"

  defstruct [:value]
end

defmodule PassiveReducersAnalytics do
  defstruct record_count: 0, total_value: 0, last_updated: nil
end

defmodule PassiveReducersTemporaryAnalyticsReducer do
  use Chronicle.Reducers.Reducer, model: PassiveReducersAnalytics, active: false

  alias PassiveReducersDataRecorded

  @handles PassiveReducersDataRecorded

  @impl true
  def reduce(%PassiveReducersDataRecorded{} = event, current, context) do
    count = if current, do: current.record_count, else: 0
    total = if current, do: current.total_value, else: 0

    %PassiveReducersAnalytics{
      record_count: count + 1,
      total_value: total + event.value,
      last_updated: Map.get(context, :occurred)
    }
  end
end
```
