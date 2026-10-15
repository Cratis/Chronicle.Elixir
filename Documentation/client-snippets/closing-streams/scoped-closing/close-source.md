```elixir
defmodule MyApp.ScopedClosingCustomerArchiver do
  alias Chronicle.EventSequences.Streams

  def archive_customer(customer_id) do
    # Every stream of this event source is closed, including its default stream.
    case Streams.complete_scope(event_source_id: customer_id) do
      {:ok, sequence_number} ->
        IO.puts("Customer archived at sequence number #{sequence_number}")

      {:error, reason} ->
        IO.puts("Not archived: #{inspect(reason)}")
    end
  end
end
```
