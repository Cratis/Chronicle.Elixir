```elixir
alias MyApp.ReadModels.Order

{:ok, orders} =
  Chronicle.ReadModels.get_instances(
    Order,
    event_count: 1_000
  )

IO.puts("Replayed #{length(orders)} orders from the capped history.")
```
