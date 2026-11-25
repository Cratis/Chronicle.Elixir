```elixir
defmodule MyApp.Events.ConcurrencyPaymentProcessed do
  use Cratis.Chronicle.Events.EventType, id: "concurrency-payment-processed"

  defstruct [:amount]
end

defmodule MyApp.Events.ConcurrencyPaymentFailed do
  use Cratis.Chronicle.Events.EventType, id: "concurrency-payment-failed"

  defstruct [:amount]
end

defmodule MyApp.Events.ConcurrencyPaymentRefunded do
  use Cratis.Chronicle.Events.EventType, id: "concurrency-payment-refunded"

  defstruct [:amount]
end

defmodule MyApp.ConcurrencyAccountService do
  alias Cratis.Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.{ConcurrencyPaymentFailed, ConcurrencyPaymentProcessed, ConcurrencyPaymentRefunded}

  def process_payment(account_id, amount) do
    # Only check concurrency for payment-related events
    scope =
      ConcurrencyScope.for_event_source(20,
        event_types: [ConcurrencyPaymentProcessed, ConcurrencyPaymentFailed, ConcurrencyPaymentRefunded]
      )

    Cratis.Chronicle.append(account_id, %ConcurrencyPaymentProcessed{amount: amount},
      concurrency_scope: scope
    )
  end
end
```
