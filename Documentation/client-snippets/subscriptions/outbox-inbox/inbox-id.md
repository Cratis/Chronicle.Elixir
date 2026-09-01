```elixir
defmodule MyApp.SubscriptionsOutboxInboxId do
  def resolve do
    # Elixir has no dedicated EventSequenceId.InboxPrefix-style helper —
    # the inbox sequence id is just a plain string wherever an
    # :event_sequence_id option is accepted.
    inbox_id = "inbox-source-event-store"
    inbox_id
  end
end
```
