```elixir title="Add/subtract functions"
defmodule MyApp.Events.DecFunctionsAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "dec-functions-account-opened"

  defstruct [:number]
end

defmodule MyApp.Events.DecFunctionsMoneyDeposited do
  use Cratis.Chronicle.Events.EventType, id: "dec-functions-money-deposited"

  defstruct [:amount]
end

defmodule MyApp.Events.DecFunctionsMoneyWithdrawn do
  use Cratis.Chronicle.Events.EventType, id: "dec-functions-money-withdrawn"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.DecFunctionsAccount do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct number: "", balance: 0
end

defmodule MyApp.Projections.DecFunctionsAccountProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecFunctionsAccount

  alias MyApp.Events.{DecFunctionsAccountOpened, DecFunctionsMoneyDeposited, DecFunctionsMoneyWithdrawn}

  from DecFunctionsAccountOpened,
    set: [balance: 0]

  from DecFunctionsMoneyDeposited,
    add: [balance: :amount]

  from DecFunctionsMoneyWithdrawn,
    subtract: [balance: :amount]
end
```
