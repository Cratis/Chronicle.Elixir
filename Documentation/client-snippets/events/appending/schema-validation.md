```elixir
case Chronicle.append(event_source_id, %MyApp.Events.OrderPlaced{
       customer_id: customer_id,
       total: total
     }) do
  :ok ->
    :ok

  # Schema failures arrive as constraint violations of type :Schema.
  {:error, {:constraint_violations, violations}} ->
    Enum.each(violations, &IO.puts("Schema error: #{&1."Message"}"))

  {:error, {:append_errors, errors}} ->
    Enum.each(errors, &IO.puts("Append error: #{inspect(&1)}"))

  {:error, reason} ->
    IO.puts("Append failed: #{inspect(reason)}")
end
```
