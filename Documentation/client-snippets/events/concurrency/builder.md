```elixir
defmodule MyApp.Events.ConcurrencyMoneyDeposited do
  use Chronicle.Events.EventType, id: "concurrency-money-deposited"

  defstruct [:amount]
end

defmodule MyApp.Events.ConcurrencyMoneyWithdrawn do
  use Chronicle.Events.EventType, id: "concurrency-money-withdrawn"

  defstruct [:amount]
end

defmodule MyApp.ConcurrencyAccountTransactionService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.{ConcurrencyMoneyDeposited, ConcurrencyMoneyWithdrawn}

  def process_transaction(account_id, amount) do
    scope =
      ConcurrencyScope.for_event_source(15,
        event_stream_type: "Transactions",
        event_types: [ConcurrencyMoneyDeposited, ConcurrencyMoneyWithdrawn]
      )

    Chronicle.append(account_id, %ConcurrencyMoneyDeposited{amount: amount},
      concurrency_scope: scope
    )
  end
end
```
