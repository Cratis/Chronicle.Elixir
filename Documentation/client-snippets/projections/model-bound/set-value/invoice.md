```elixir
defmodule MyApp.Events.SetValueInvoiceIssued do
  use Chronicle.Events.EventType, id: "set-value-invoice-issued-v1"

  defstruct [:amount]
end

defmodule MyApp.Events.SetValueInvoicePaid do
  use Chronicle.Events.EventType, id: "set-value-invoice-paid-v1"

  defstruct []
end

defmodule MyApp.ReadModels.SetValueInvoice do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{SetValueInvoiceIssued, SetValueInvoicePaid}

  defstruct [:id, amount: 0, status: ""]

  from SetValueInvoiceIssued,
    set: [id: :event_source_id, amount: :amount, status: "$value(issued)"]

  from SetValueInvoicePaid,
    set: [status: "$value(paid)"]
end
```
