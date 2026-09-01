```elixir
defmodule PassiveReducersAccountBalance do
  defstruct balance: 0
end

defmodule PassiveReducersHistoricalBalanceService do
  # A passive reducer computes state on-demand from the full history of
  # events — Chronicle.read_model/2 triggers that computation.
  def get_balance_at_date(account_id, _date) do
    Chronicle.read_model(PassiveReducersAccountBalance, account_id)
  end
end
```
