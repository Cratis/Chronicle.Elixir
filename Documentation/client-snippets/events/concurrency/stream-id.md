```elixir
defmodule MyApp.Events.ConcurrencyMonthlyReportGenerated do
  use Cratis.Chronicle.Events.EventType, id: "concurrency-monthly-report-generated"

  defstruct [:month]
end

defmodule MyApp.ConcurrencyMonthlyReportService do
  alias Cratis.Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyMonthlyReportGenerated

  def generate_monthly_report(account_id, month_key) do
    scope =
      ConcurrencyScope.for_event_source(5,
        event_stream_type: "Reporting",
        event_stream_id: month_key
      )

    Cratis.Chronicle.append(
      account_id,
      %ConcurrencyMonthlyReportGenerated{month: month_key},
      event_stream_type: "Reporting",
      event_stream_id: month_key,
      concurrency_scope: scope
    )
  end
end
```
