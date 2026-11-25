```elixir
{:ok, result} =
  Cratis.Chronicle.Projections.query(
    """
    projection InboxMessages
      from MessageReceived
    """,
    event_sequence_id: "inbox"
  )

Enum.each(result.instances, &IO.inspect/1)
```
