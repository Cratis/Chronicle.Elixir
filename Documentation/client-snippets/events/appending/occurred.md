```elixir
{:ok, occurred, 0} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

:ok =
  Chronicle.append(
    event_source_id,
    %MyApp.Events.OrderPlaced{customer_id: customer_id, total: total},
    occurred: occurred
  )
```
