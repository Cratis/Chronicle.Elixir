```elixir
defmodule PassiveReducersReportingService do
  # This triggers the passive reducer to compute state from events on demand.
  def generate_report(report_id) do
    Chronicle.read_model(PassiveReducersMonthlyRevenueReport, report_id)
  end
end
```
