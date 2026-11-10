```elixir
defmodule MyApp.Events.LegacyInvoiceIssued do
  use Chronicle.Events.EventType, id: "legacy-invoice-issued"

  defstruct number: ""
end

defmodule MyApp.InvoiceMigration do
  alias Chronicle.EventSequences.EventForEventSourceId

  def resume(import_id, source) do
    with {:ok, session} <- Chronicle.Imports.reattach(import_id) do
      # The kernel already holds the first events_acknowledged events; continue with the rest.
      remaining =
        source
        |> Stream.drop(session.events_acknowledged)
        |> Stream.map(fn {invoice_id, number} ->
          %EventForEventSourceId{
            event_source_id: invoice_id,
            event: %MyApp.Events.LegacyInvoiceIssued{number: number}
          }
        end)

      with {:ok, session} <- Chronicle.Imports.add(session, remaining) do
        Chronicle.Imports.complete(session)
      end
    end
  end
end
```
