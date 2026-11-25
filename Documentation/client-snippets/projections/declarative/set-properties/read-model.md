```elixir
defmodule MyApp.ReadModels.DecSetPropsAccount do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [
    :account_number,
    :customer_name,
    :balance,
    :is_active,
    :opened_at,
    :last_transaction
  ]
end
```
