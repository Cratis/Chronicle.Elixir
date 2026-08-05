```elixir
defmodule MyApp.EventSequencesWaitForCompletion do
  def place_order_and_wait(event_source_id, event) do
    case Chronicle.EventSequences.EventLog.append_and_wait_for_completion(event_source_id, event) do
      {:ok, %{success: true, failed_partitions: []}} -> :ok
      {:ok, %{success: false, failed_partitions: _failed_partitions}} -> :error
      {:error, _reason} -> :error
    end
  end
end
```
