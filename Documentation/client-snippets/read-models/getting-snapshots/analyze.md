```elixir
alias MyApp.ReadModels.Order

{:ok, snapshots} = Chronicle.ReadModels.get_snapshots_by_id(Order, order_id)

Enum.each(snapshots, fn snapshot ->
  IO.puts("Snapshot at #{snapshot.occurred}")
  IO.puts("  Correlation ID: #{snapshot.correlation_id}")
  IO.puts("  Event count: #{length(snapshot.events)}")
  IO.inspect(snapshot.read_model, label: "  State")
end)
```
