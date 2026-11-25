```elixir
defmodule MyApp.EventSequencesRedactSingleEvent do
  def redact_event(sequence_number, reason) do
    Cratis.Chronicle.EventSequences.EventLog.redact(sequence_number, reason)
  end
end
```
