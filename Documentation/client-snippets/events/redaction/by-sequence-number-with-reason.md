```elixir
defmodule MyApp.RedactionWithReasonService do
  alias Chronicle.EventSequences.EventLog

  def redact(sequence_number) do
    EventLog.redact(sequence_number, "GDPR erasure request")
  end
end
```
