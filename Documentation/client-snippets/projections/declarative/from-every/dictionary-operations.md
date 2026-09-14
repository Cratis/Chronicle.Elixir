```elixir title="Dictionary increment/decrement in declarative projections"
defmodule MyApp.Events.MessageSent do
  use Chronicle.Events.EventType, id: "message-sent-v1"

  defstruct [:conversation_id, :content]
end

defmodule MyApp.Events.MessageDeleted do
  use Chronicle.Events.EventType, id: "message-deleted-v1"

  defstruct [:conversation_id, :message_id]
end

defmodule MyApp.ReadModels.ConversationStatistics do
  use Chronicle.ReadModels.ReadModel

  defstruct [:conversation_id, :message_counts, :deletion_counts]
end

defmodule MyApp.Projections.ConversationStatisticsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.ConversationStatistics

  alias MyApp.Events.{MessageSent, MessageDeleted}

  from MessageSent,
    set: [conversation_id: :event_source_id]

  from MessageDeleted

  # Track both message additions and deletions per event type
  from_every increment: [message_counts: {:event_context, :type}]
  from_every decrement: [deletion_counts: {:event_context, :type}]
end
```

This declarative projection maintains two separate dictionary fields:

- `message_counts` increments for each event type
- `deletion_counts` decrements for each event type

Chronicle will produce read models like:

```elixir
%MyApp.ReadModels.ConversationStatistics{
  conversation_id: "conv-123",
  message_counts: %{
    "message-sent-v1" => 50,
    "message-deleted-v1" => 5
  },
  deletion_counts: %{
    "message-sent-v1" => -50,
    "message-deleted-v1" => -5
  }
}
```

You can combine simple increment/decrement (without dictionary keys) with dictionary operations:

```elixir
from_every increment: [total_events: 1, event_type_counts: {:event_context, :type}]
```

This increments a simple counter `total_events` by 1 for every event, and also maintains
a per-type count in the `event_type_counts` dictionary.
