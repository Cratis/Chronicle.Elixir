```elixir title="Add from an event"
defmodule MyApp.Events.AccountOpenedForDeposits do
  use Chronicle.Events.EventType, id: "account-opened-for-deposits-v1"

  defstruct [:initial_balance]
end

defmodule MyApp.Events.DepositMadeForBalance do
  use Chronicle.Events.EventType, id: "deposit-made-for-balance-v1"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.DepositAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{AccountOpenedForDeposits, DepositMadeForBalance}

  defstruct [:id, balance: 0]

  from AccountOpenedForDeposits,
    set: [
      id: :event_source_id,
      balance: :initial_balance
    ]

  from DepositMadeForBalance,
    add: [balance: :amount]
end
```
