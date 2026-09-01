```elixir
defmodule EventProcessingHourlyMetricRecorded do
  use Chronicle.Events.EventType, id: "event-processing-hourly-metric-recorded"

  defstruct [:value]
end

defmodule EventProcessingHourlyMetrics do
  defstruct metrics_by_hour: %{}
end

defmodule EventProcessingHourlyMetricsReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingHourlyMetrics

  alias EventProcessingHourlyMetricRecorded

  @handles EventProcessingHourlyMetricRecorded

  @impl true
  def reduce(%EventProcessingHourlyMetricRecorded{} = event, current, context) do
    metrics_by_hour = if current, do: current.metrics_by_hour, else: %{}
    {:ok, occurred, _} = DateTime.from_iso8601(Map.get(context, :occurred))

    updated = Map.update(metrics_by_hour, occurred.hour, event.value, &(&1 + event.value))

    %EventProcessingHourlyMetrics{metrics_by_hour: updated}
  end
end
```
