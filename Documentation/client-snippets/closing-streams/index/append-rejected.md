```elixir
defmodule MyApp.Events.ClosingStreamsInvoiceLineAdded do
  use Chronicle.Events.EventType, id: "closing-streams-invoice-line-added"

  defstruct [:description, :amount]
end

defmodule MyApp.ClosingStreamsInvoiceLineAppender do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.ClosingStreamsInvoiceLineAdded

  def try_append_line(invoice_id) do
    case EventLog.append(
           invoice_id,
           %ClosingStreamsInvoiceLineAdded{description: "Consulting", amount: 500},
           event_stream_type: "invoices",
           event_stream_id: "invoice-42"
         ) do
      :ok ->
        true

      {:error, {:constraint_violations, violations}} ->
        not Enum.any?(violations, &stream_closed?/1)

      {:error, _reason} ->
        true
    end
  end

  # Mirrors the wire Constraint's Type field (seen as :Unique / :UniqueEventType
  # when registering constraints) — a rejection caused by a closed stream comes
  # back as a violation whose type is :StreamClosed.
  defp stream_closed?(violation) when is_map(violation) do
    Map.get(violation, :Type) == :StreamClosed or Map.get(violation, :type) == :stream_closed
  end

  defp stream_closed?(_violation), do: false
end
```
