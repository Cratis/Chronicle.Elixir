```elixir
defmodule MyApp.EventSequencesCompleteStream do
  def complete_audit_trail do
    case Chronicle.EventSequences.EventLog.complete_stream("audit-trail", "2024") do
      {:ok, _tail_sequence_number} -> :ok
      {:error, :default_stream_cannot_be_completed} -> :error
      {:error, :already_completed} -> :ok
    end
  end
end
```
