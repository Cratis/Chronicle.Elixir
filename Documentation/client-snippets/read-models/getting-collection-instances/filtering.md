```elixir
alias MyApp.ReadModels.Account

{:ok, accounts} = Chronicle.ReadModels.get_instances(Account)

high_value_accounts =
  accounts
  |> Enum.filter(&(&1.balance > threshold))
  |> Enum.sort_by(& &1.balance, :desc)

IO.inspect(high_value_accounts, label: "High-value accounts")
```
