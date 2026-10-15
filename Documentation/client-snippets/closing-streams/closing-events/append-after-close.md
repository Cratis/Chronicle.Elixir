```elixir
defmodule MyApp.Events.ClosingEventsLedgerPeriodClosed do
  use Chronicle.Events.EventType, id: "closing-events-ledger-period-closed"

  defstruct [:period, :closing_balance]

  closes_stream event_stream_id_from: :period
end

defmodule MyApp.Events.ClosingEventsEntryPosted do
  use Chronicle.Events.EventType, id: "closing-events-entry-posted"

  defstruct [:description]
end

defmodule MyApp.ClosingEventsAfterClose do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConstraintViolation
  alias MyApp.Events.{ClosingEventsEntryPosted, ClosingEventsLedgerPeriodClosed}

  def run(ledger_id) do
    :ok =
      EventLog.append(
        ledger_id,
        %ClosingEventsLedgerPeriodClosed{period: "2026-04", closing_balance: 1200},
        event_stream_type: "ledger",
        event_stream_id: "2026-04"
      )

    late =
      EventLog.append_with_result(
        ledger_id,
        %ClosingEventsEntryPosted{description: "Late invoice"},
        event_stream_type: "ledger",
        event_stream_id: "2026-04"
      )

    # The late entry is refused; the next period is unaffected.
    case late do
      {:error, %{constraint_violations: violations}} -> Enum.any?(violations, &stream_closed?/1)
      _ -> false
    end
  end

  # A rejection caused by a closed stream carries the closure's details.
  defp stream_closed?(violation),
    do: Map.has_key?(ConstraintViolation.details(violation), :closed_by)
end
```
