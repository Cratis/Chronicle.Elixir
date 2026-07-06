```elixir title="Subtract from an event"
defmodule MyApp.Events.BalanceAccountOpened do
  use Chronicle.Events.EventType, id: "balance-account-opened-v1"

  defstruct [:initial_balance]
end

defmodule MyApp.Events.BalanceDepositMade do
  use Chronicle.Events.EventType, id: "balance-deposit-made-v1"

  defstruct [:amount]
end

defmodule MyApp.Events.BalanceWithdrawalMade do
  use Chronicle.Events.EventType, id: "balance-withdrawal-made-v1"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.BalanceAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{BalanceAccountOpened, BalanceDepositMade, BalanceWithdrawalMade}

  defstruct [:id, balance: 0]

  from BalanceAccountOpened,
    set: [
      id: :event_source_id,
      balance: :initial_balance
    ]

  from BalanceDepositMade,
    add: [balance: :amount]

  from BalanceWithdrawalMade,
    subtract: [balance: :amount]
end
```
