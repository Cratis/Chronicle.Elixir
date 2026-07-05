```elixir
defmodule MyApp.Events.ReducersIndexDepositMade do
  use Chronicle.Events.EventType, id: "reducers-index-deposit-made"

  defstruct [:amount]
end

defmodule MyApp.Events.ReducersIndexWithdrawalMade do
  use Chronicle.Events.EventType, id: "reducers-index-withdrawal-made"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.ReducersIndexAccountBalance do
  defstruct balance: 0, last_updated: nil
end

defmodule MyApp.Reducers.ReducersIndexAccountBalanceReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.ReducersIndexAccountBalance

  alias MyApp.Events.{ReducersIndexDepositMade, ReducersIndexWithdrawalMade}
  alias MyApp.ReadModels.ReducersIndexAccountBalance

  @handles ReducersIndexDepositMade
  @handles ReducersIndexWithdrawalMade

  @impl true
  def reduce(%ReducersIndexDepositMade{} = event, current, context) do
    current_balance = if current, do: current.balance, else: 0

    %ReducersIndexAccountBalance{
      balance: current_balance + event.amount,
      last_updated: Map.get(context, :occurred)
    }
  end

  def reduce(%ReducersIndexWithdrawalMade{} = event, current, context) do
    current_balance = if current, do: current.balance, else: 0

    %ReducersIndexAccountBalance{
      balance: current_balance - event.amount,
      last_updated: Map.get(context, :occurred)
    }
  end
end
```
