```elixir
defmodule EventProcessingMetricRecorded do
  use Chronicle.Events.EventType, id: "event-processing-metric-recorded"

  defstruct [:value]
end

defmodule EventProcessingStatistics do
  defstruct sum: 0, count: 0, average: 0
end

defmodule EventProcessingStatisticsReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingStatistics

  alias EventProcessingMetricRecorded

  @handles EventProcessingMetricRecorded

  @impl true
  def reduce(%EventProcessingMetricRecorded{} = event, current, _context) do
    sum = (if current, do: current.sum, else: 0) + event.value
    count = (if current, do: current.count, else: 0) + 1

    %EventProcessingStatistics{sum: sum, count: count, average: sum / count}
  end
end
```
