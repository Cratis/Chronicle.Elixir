```elixir
defmodule MyApp.ScopedClosingErrorHandling do
  alias Chronicle.EventSequences.Streams

  def close(scope) when is_list(scope) do
    case Streams.complete_scope(scope) do
      {:ok, sequence_number} -> "Closed at #{sequence_number}"
      {:error, :already_completed} -> "Already closed by an earlier manual close"
      {:error, :default_stream_cannot_be_completed} -> "The default stream cannot be closed on its own"
      {:error, :empty_scope} -> "The scope names no dimension"
      {:error, :expected_tail_mismatch} -> "Something landed in the scope since you last looked"
      {:error, other} -> "Unexpected error #{inspect(other)}"
    end
  end
end
```
