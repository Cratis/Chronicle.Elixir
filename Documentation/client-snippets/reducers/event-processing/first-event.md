```elixir
defmodule EventProcessingDataRecorded do
  use Chronicle.Events.EventType, id: "event-processing-data-recorded"

  defstruct [:value]
end

defmodule EventProcessingAnalytics do
  defstruct [:event_count, :first_event_time, :last_event_time, :total_value]
end

defmodule EventProcessingAnalyticsReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingAnalytics

  alias EventProcessingDataRecorded

  @handles EventProcessingDataRecorded

  @impl true
  def reduce(%EventProcessingDataRecorded{} = event, nil, context) do
    occurred = Map.get(context, :occurred)

    %EventProcessingAnalytics{
      event_count: 1,
      first_event_time: occurred,
      last_event_time: occurred,
      total_value: event.value
    }
  end

  def reduce(%EventProcessingDataRecorded{} = event, current, context) do
    %{
      current
      | event_count: current.event_count + 1,
        last_event_time: Map.get(context, :occurred),
        total_value: current.total_value + event.value
    }
  end
end
```
