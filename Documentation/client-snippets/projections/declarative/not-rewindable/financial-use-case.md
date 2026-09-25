```elixir
defmodule MyApp.Events.DecNotRewindablePaymentProcessed do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-payment-processed"

  defstruct payment_id: "", amount: 0.0
end

defmodule MyApp.ReadModels.DecNotRewindableLedgerEntry do
  use Chronicle.ReadModels.ReadModel

  defstruct recorded_at: nil, transaction_type: nil
end

defmodule MyApp.Projections.DecNotRewindableTransactionLedgerProjection do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecNotRewindableLedgerEntry,
    not_rewindable: true

  from_every set: [recorded_at: :occurred]

  from MyApp.Events.DecNotRewindablePaymentProcessed,
    set: [transaction_type: "$value(PAYMENT)"]
end
```
