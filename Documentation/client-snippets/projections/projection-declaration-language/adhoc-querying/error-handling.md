```elixir
case Chronicle.Projections.query("""
     projection Orders
       from OrderPlaced
     """) do
  {:ok, _result} -> :ok
  {:error, {:invalid_declaration, errors}} -> Enum.each(errors, &IO.inspect/1)
end
```
