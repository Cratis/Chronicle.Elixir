```elixir
defmodule BatchAccountOpened do
  use Chronicle.Events.EventType, id: "batch-account-opened"

  defstruct owner: ""
end

defmodule BatchMoneyDeposited do
  use Chronicle.Events.EventType, id: "batch-money-deposited"

  defstruct amount: 0
end

defmodule BatchMoneyWithdrawn do
  use Chronicle.Events.EventType, id: "batch-money-withdrawn"

  defstruct amount: 0
end

defmodule BatchAccount do
  use Chronicle.ReadModels.ReadModel

  defstruct owner: "", balance: 0
end

defmodule BatchAccountReducer do
  use Chronicle.Reducers.Reducer, model: BatchAccount

  # Called once per account in a page, with its events and its stored state.
  @observes BatchAccountOpened
  @observes BatchMoneyDeposited
  @observes BatchMoneyWithdrawn
  def fold(events, current, _context) do
    Enum.reduce(events, current, fn
      {%BatchAccountOpened{owner: owner}, _context}, _account ->
        %BatchAccount{owner: owner}

      {%BatchMoneyDeposited{amount: amount}, _context}, account ->
        %{account | balance: account.balance + amount}

      {%BatchMoneyWithdrawn{amount: amount}, _context}, account ->
        %{account | balance: account.balance - amount}
    end)
  end
end
```
