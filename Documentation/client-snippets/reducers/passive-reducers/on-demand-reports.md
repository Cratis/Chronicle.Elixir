```elixir
defmodule PassiveReducersPaymentReceived do
  use Chronicle.Events.EventType, id: "passive-reducers-payment-received"

  defstruct [:category, :amount]
end

defmodule PassiveReducersMonthlyRevenueReport do
  defstruct total_revenue: 0, revenue_by_category: %{}, month: nil, year: nil
end

defmodule PassiveReducersMonthlyRevenueReportReducer do
  use Chronicle.Reducers.Reducer, model: PassiveReducersMonthlyRevenueReport, active: false

  alias PassiveReducersPaymentReceived

  @handles PassiveReducersPaymentReceived

  @impl true
  def reduce(%PassiveReducersPaymentReceived{} = event, current, context) do
    revenue = if current, do: current.total_revenue, else: 0
    by_category = if current, do: current.revenue_by_category, else: %{}

    updated_by_category =
      Map.update(by_category, event.category, event.amount, &(&1 + event.amount))

    {:ok, occurred, _} = DateTime.from_iso8601(Map.get(context, :occurred))

    %PassiveReducersMonthlyRevenueReport{
      total_revenue: revenue + event.amount,
      revenue_by_category: updated_by_category,
      month: occurred.month,
      year: occurred.year
    }
  end
end
```
