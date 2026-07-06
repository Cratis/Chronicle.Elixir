```elixir
alias MyApp.ReadModels.AccountInfo

{:ok, account} = Chronicle.ReadModels.get_instance_by_id(AccountInfo, account_id)

if account do
  IO.puts("#{account.name}: #{account.balance}")
end
```
