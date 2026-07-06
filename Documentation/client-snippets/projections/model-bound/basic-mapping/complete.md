```elixir title="Complete balance projection"
defmodule MyApp.Events.BankAccountOpened do
  use Chronicle.Events.EventType, id: "bank-account-opened-v1"

  defstruct [:account_name, :initial_balance]
end

defmodule MyApp.Events.BankAccountRenamed do
  use Chronicle.Events.EventType, id: "bank-account-renamed-v1"

  defstruct [:new_name]
end

defmodule MyApp.Events.FundsDeposited do
  use Chronicle.Events.EventType, id: "funds-deposited-v1"

  defstruct [:amount]
end

defmodule MyApp.Events.FundsWithdrawn do
  use Chronicle.Events.EventType, id: "funds-withdrawn-v1"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.BankAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{BankAccountOpened, BankAccountRenamed, FundsDeposited, FundsWithdrawn}

  defstruct [:id, :name, balance: 0]

  from BankAccountOpened,
    set: [
      id: :event_source_id,
      name: :account_name,
      balance: :initial_balance
    ]

  from BankAccountRenamed,
    set: [name: :new_name]

  from FundsDeposited,
    add: [balance: :amount]

  from FundsWithdrawn,
    subtract: [balance: :amount]
end
```
