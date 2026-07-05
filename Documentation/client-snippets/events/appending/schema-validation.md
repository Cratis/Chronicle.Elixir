```elixir
case Chronicle.append(event_source_id, %MyApp.Events.OrderPlaced{
       customer_id: customer_id,
       total: total
     }) do
  :ok ->
    :ok

  {:error, {:append_errors, errors}} ->
    Enum.each(errors, &IO.puts("Schema error: #{inspect(&1)}"))
end
```
