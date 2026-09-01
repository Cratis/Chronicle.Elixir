```elixir
defmodule MyApp.GettingEventsTailReader do
  alias Chronicle.EventSequences.EventLog

  def read_last(count) do
    # Reads from the computed start and trims in memory to the requested count.
    with {:ok, tail} <- EventLog.get_tail_sequence_number() do
      start = if tail >= count, do: tail - (count - 1), else: 0

      with {:ok, events} <- EventLog.get_from_sequence_number(start) do
        {:ok, Enum.take(events, -count)}
      end
    end
  end
end
```
