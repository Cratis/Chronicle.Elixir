```elixir
defmodule MyApp.Events.ScopedClosingReportApproved do
  use Chronicle.Events.EventType, id: "scoped-closing-report-approved"

  defstruct [:approver]
end

defmodule MyApp.ScopedClosingApprover do
  alias Chronicle.EventSequences.{EventLog, Streams}
  alias MyApp.Events.ScopedClosingReportApproved

  def approve_and_close(report_id) do
    with {:ok, approved} <-
           EventLog.append_with_result(
             report_id,
             %ScopedClosingReportApproved{approver: "alice"},
             event_stream_type: "monthly-report",
             event_stream_id: "2026-04"
           ) do
      # Close only if nothing has landed in this scope after the approval.
      result =
        Streams.complete_scope(
          event_source_id: report_id,
          event_stream_type: "monthly-report",
          event_stream_id: "2026-04",
          expected_tail_sequence_number: approved.sequence_number
        )

      match?({:ok, _}, result) or result == {:error, :already_completed}
    else
      {:error, _result} -> false
    end
  end
end
```
