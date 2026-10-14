```elixir
# Inferred — schema derived from OrderPlaced and OrderShipped event properties, entries decode
# as plain maps.
{:ok, inferred} =
  Chronicle.Projections.query("""
  projection Orders
    from OrderPlaced
    from OrderShipped
  """)

# Explicit — assuming an Order read model is registered under the id "Order"; entries decode
# as %MyApp.ReadModels.Order{} structs.
{:ok, explicit} =
  Chronicle.Projections.query(
    """
    projection Orders => Order
      from OrderPlaced
      from OrderShipped
    """,
    read_model: MyApp.ReadModels.Order
  )

IO.inspect(inferred.instances)
IO.inspect(explicit.instances)
```
