```elixir
defmodule MyApp.InspectingIsCompleted do
  alias Chronicle.EventSequences.Streams

  def april_closed?(report_id) do
    {:ok, completed?} =
      Streams.scope_completed?(
        event_source_id: report_id,
        event_stream_type: "monthly-report",
        event_stream_id: "2026-04"
      )

    completed?
  end
end
```
