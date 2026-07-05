```elixir
defmodule MyApp.GettingStateCheckpointStore do
  def capture_tail do
    # Persists the current tail so processing can resume later.
    Chronicle.get_tail_sequence_number()
  end
end
```
