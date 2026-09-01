```elixir
defmodule MyApp.RedactionByEventSourceService do
  alias Chronicle.EventSequences.EventLog

  def redact_account(event_source_id) do
    EventLog.redact_for_event_source(event_source_id, "Account deletion requested")
  end
end
```
