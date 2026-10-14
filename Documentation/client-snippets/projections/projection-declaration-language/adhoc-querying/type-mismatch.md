```elixir
# This declaration returns {:error, {:invalid_declaration, _}}:
# OrderPlaced.value is a string, but OrderShipped.value is an integer
{:error, {:invalid_declaration, _errors}} =
  Chronicle.Projections.query("""
  projection Bad
    from OrderPlaced
    from OrderShipped
  """)
```
