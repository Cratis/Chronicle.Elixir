```elixir
{:ok, result} =
  Cratis.Chronicle.Projections.query("""
  projection OrderSummary
    from OrderPlaced
  """)

Enum.each(result.instances, &IO.inspect/1)
```
