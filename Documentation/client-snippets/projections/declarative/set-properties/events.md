```elixir
defmodule MyApp.Events.DecSetPropsCustomer do
  defstruct [:name, :email]
end

defmodule MyApp.Events.DecSetPropsAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "dec-set-props-account-opened"

  defstruct [:number, :owner, :timestamp]
end

defmodule MyApp.Events.DecSetPropsMoneyDeposited do
  use Cratis.Chronicle.Events.EventType, id: "dec-set-props-money-deposited"

  defstruct [:amount, :timestamp]
end
```
