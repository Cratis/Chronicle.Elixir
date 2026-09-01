```elixir
defmodule EventProcessingPatternWithContextMetricRecorded do
  use Chronicle.Events.EventType, id: "event-processing-pattern-with-context-metric-recorded"

  defstruct [:value]
end

defmodule EventProcessingPatternWithContextStats do
  defstruct [:total, :last_updated]
end

defmodule EventProcessingPatternWithContextReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingPatternWithContextStats

  alias EventProcessingPatternWithContextMetricRecorded

  @handles EventProcessingPatternWithContextMetricRecorded

  # Access occurred time, sequence number, and other metadata through the
  # third `context` argument.
  @impl true
  def reduce(%EventProcessingPatternWithContextMetricRecorded{} = event, current, context) do
    total = if current, do: current.total, else: 0

    %EventProcessingPatternWithContextStats{
      total: total + event.value,
      last_updated: Map.get(context, :occurred)
    }
  end
end
```
