```elixir
defmodule MyApp.EventSequencesSequenceNumbers do
  def tail_and_next(event_source_id) do
    {:ok, tail} = Chronicle.EventSequences.EventLog.get_tail_sequence_number(event_source_id)
    {:ok, next} = Chronicle.EventSequences.EventLog.get_next_sequence_number(event_source_id)
    {tail, next}
  end
end
```
