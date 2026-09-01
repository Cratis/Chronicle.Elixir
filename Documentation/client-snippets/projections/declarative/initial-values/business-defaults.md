```elixir title="Business defaults"
defmodule MyApp.Events.DecInitialValuesOrderSubmitted do
  use Chronicle.Events.EventType, id: "dec-initial-values-order-submitted"

  defstruct [:customer_name, :total_amount]
end

defmodule MyApp.ReadModels.DecInitialValuesOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct customer_name: "",
            status: "Draft",
            total_amount: 0,
            submitted_at: ~U[1970-01-01 00:00:00Z],
            notes: "No notes"
end

defmodule MyApp.Projections.DecInitialValuesOrderSummaryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecInitialValuesOrderSummary

  alias MyApp.Events.DecInitialValuesOrderSubmitted

  from DecInitialValuesOrderSubmitted,
    set: [
      status: "$value(Submitted)",
      submitted_at: :occurred
    ]
end
```
