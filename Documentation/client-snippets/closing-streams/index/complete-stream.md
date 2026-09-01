```elixir
defmodule MyApp.ClosingStreamsInvoiceCloser do
  alias Chronicle.EventSequences.EventLog

  def close_invoice_stream(invoice_stream_id) do
    case EventLog.complete_stream("invoices", invoice_stream_id) do
      {:ok, sequence_number} ->
        IO.puts("Stream closed at sequence number #{sequence_number}")

      {:error, reason} ->
        IO.puts("Failed to close stream: #{inspect(reason)}")
    end
  end
end
```
