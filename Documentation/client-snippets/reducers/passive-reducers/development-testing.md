```elixir
defmodule PassiveReducersExperimentalMetricRecorded do
  use Chronicle.Events.EventType, id: "passive-reducers-experimental-metric-recorded"

  defstruct [:value]
end

defmodule PassiveReducersExperimentalMetrics do
  defstruct sample_count: 0
end

defmodule PassiveReducersExperimentalMetricsReducer do
  # Mix.env/0 is evaluated at compile time, so a release build always sees
  # `active: true` — only local :dev builds register without activating.
  use Chronicle.Reducers.Reducer,
    model: PassiveReducersExperimentalMetrics,
    active: Mix.env() != :dev

  alias PassiveReducersExperimentalMetricRecorded

  @handles PassiveReducersExperimentalMetricRecorded

  @impl true
  def reduce(%PassiveReducersExperimentalMetricRecorded{}, current, _context) do
    count = if current, do: current.sample_count, else: 0
    %PassiveReducersExperimentalMetrics{sample_count: count + 1}
  end
end
```
