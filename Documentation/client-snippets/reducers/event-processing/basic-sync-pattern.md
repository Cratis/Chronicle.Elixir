```elixir
defmodule EventProcessingBasicSyncPatternMetricRecorded do
  use Chronicle.Events.EventType, id: "event-processing-basic-sync-pattern-metric-recorded"

  defstruct [:value]
end

defmodule EventProcessingBasicSyncPatternStats do
  defstruct total: 0
end

defmodule EventProcessingBasicSyncPatternReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingBasicSyncPatternStats

  alias EventProcessingBasicSyncPatternMetricRecorded

  @handles EventProcessingBasicSyncPatternMetricRecorded

  # The simplest pattern: the event and the current state. Elixir's reduce/3
  # always receives a third context argument too — ignore it with `_` when
  # you don't need it.
  @impl true
  def reduce(%EventProcessingBasicSyncPatternMetricRecorded{} = event, current, _context) do
    total = if current, do: current.total, else: 0
    %EventProcessingBasicSyncPatternStats{total: total + event.value}
  end
end
```
