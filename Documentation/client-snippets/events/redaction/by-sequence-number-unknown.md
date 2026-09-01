```elixir
defmodule MyApp.RedactionUnknownReasonService do
  alias Chronicle.EventSequences.EventLog

  def redact(sequence_number) do
    EventLog.redact(sequence_number, "Unknown")
  end
end
```
