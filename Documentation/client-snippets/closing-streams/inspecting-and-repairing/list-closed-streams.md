```elixir
defmodule MyApp.InspectingClosedStreams do
  alias Chronicle.EventSequences.Streams

  def print(report_id) do
    # Everything closed for one event source. Omit the options to list every closure.
    {:ok, closed_streams} = Streams.closed(event_source_id: report_id)

    for closed <- closed_streams do
      owner =
        if closed.origin == :closing_event,
          do: "closing event constraint '#{closed.closed_by}'",
          else: "manual complete_stream"

      IO.puts(
        "#{closed.event_stream_type}/#{closed.event_stream_id} closed at " <>
          "#{closed.sequence_number} (#{closed.closed_at}) by #{owner}"
      )
    end
  end
end
```
