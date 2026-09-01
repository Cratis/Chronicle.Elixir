```elixir
defmodule MyApp.GettingEventsReplayEvents do
  alias Chronicle.EventSequences.EventLog

  def read_from(sequence_number) do
    # Replays from a known checkpoint to rebuild projections or read models.
    EventLog.get_from_sequence_number(sequence_number)
  end
end
```
