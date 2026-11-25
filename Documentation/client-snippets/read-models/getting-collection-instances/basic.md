```elixir
alias MyApp.ReadModels.Account

{:ok, accounts} = Cratis.Chronicle.ReadModels.get_instances(Account)

Enum.each(accounts, fn account ->
  IO.puts("#{account.name}: #{account.balance}")
end)
```
