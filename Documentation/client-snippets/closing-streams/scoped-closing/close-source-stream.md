```elixir
defmodule MyApp.ScopedClosingReportCloser do
  alias Chronicle.EventSequences.Streams

  def close_approved_report(report_id) do
    # Close one report's "2026-04" stream. Other reports that use the same
    # stream type and stream id stay open.
    result =
      Streams.complete_scope(
        event_source_id: report_id,
        event_stream_type: "monthly-report",
        event_stream_id: "2026-04"
      )

    case result do
      {:ok, sequence_number} -> IO.puts("Closed at sequence number #{sequence_number}")
      {:error, reason} -> IO.puts("Not closed: #{inspect(reason)}")
    end
  end
end
```
