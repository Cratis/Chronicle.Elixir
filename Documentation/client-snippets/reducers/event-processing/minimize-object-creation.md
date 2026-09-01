```elixir
defmodule EventProcessingMinimalMetricRecorded do
  use Chronicle.Events.EventType, id: "event-processing-minimal-metric-recorded"

  defstruct [:value]
end

defmodule EventProcessingMinimalStats do
  defstruct count: 0, sum: 0
end

defmodule EventProcessingMinimalStatsReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingMinimalStats

  alias EventProcessingMinimalMetricRecorded

  @handles EventProcessingMinimalMetricRecorded

  @impl true
  def reduce(%EventProcessingMinimalMetricRecorded{} = event, nil, _context) do
    %EventProcessingMinimalStats{count: 1, sum: event.value}
  end

  def reduce(%EventProcessingMinimalMetricRecorded{} = event, current, _context) do
    %{current | count: current.count + 1, sum: current.sum + event.value}
  end
end
```
