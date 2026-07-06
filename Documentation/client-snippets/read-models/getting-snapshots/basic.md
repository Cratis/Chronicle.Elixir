```elixir
alias MyApp.ReadModels.Order

{:ok, snapshots} = Chronicle.ReadModels.get_snapshots_by_id(Order, order_id)

IO.puts("Found #{length(snapshots)} snapshots.")
```
