```elixir
defmodule MyApp.EventSequencesRedactForEventSource do
  def redact_customer(event_source_id) do
    Cratis.Chronicle.EventSequences.EventLog.redact_for_event_source(
      event_source_id,
      "Account closed under GDPR"
    )
  end
end
```
