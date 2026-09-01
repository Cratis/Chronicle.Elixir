```elixir
defmodule MyApp.Events.TaggingDynamicPatternsEventOccurred do
  use Chronicle.Events.EventType, id: "tagging-dynamic-patterns-event-occurred"

  defstruct [:data]
end

defmodule MyApp.TaggingDynamicPatternsService do
  alias MyApp.Events.TaggingDynamicPatternsEventOccurred

  def record_production_critical(event_source_id) do
    Chronicle.append(
      event_source_id,
      %TaggingDynamicPatternsEventOccurred{data: "production issue"},
      tags: ["production", "critical"]
    )
  end

  def record_development_test(event_source_id) do
    Chronicle.append(
      event_source_id,
      %TaggingDynamicPatternsEventOccurred{data: "test run"},
      tags: ["development", "testing"]
    )
  end

  def record_batch_migration(event_source_id) do
    Chronicle.append(
      event_source_id,
      %TaggingDynamicPatternsEventOccurred{data: "batch migration"},
      tags: ["migration", "batch-process"]
    )
  end
end
```
