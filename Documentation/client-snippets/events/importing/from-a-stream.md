```elixir
defmodule MyApp.Events.LegacyCustomerRegistered do
  use Chronicle.Events.EventType, id: "legacy-customer-registered"

  defstruct name: ""
end

defmodule MyApp.CustomerMigration do
  alias Chronicle.EventSequences.EventForEventSourceId

  # rows is any Enumerable, a lazy Stream included: it is read while the import uploads.
  def run(rows) do
    rows
    |> Stream.map(&to_event/1)
    |> Chronicle.Imports.import(on_invalid: :reject, progress: self())
  end

  def report_progress do
    receive do
      {:chronicle_import_progress, _import_id, progress} ->
        IO.puts("#{progress.state}: #{progress.events_committed} committed")
    end
  end

  defp to_event(%{event_id: event_id, customer_id: customer_id, name: name, at: at, position: position}) do
    %EventForEventSourceId{
      event_source_id: customer_id,
      event: %MyApp.Events.LegacyCustomerRegistered{name: name},
      occurred: at,
      idempotency_key: event_id,
      source_sequence_number: position
    }
  end
end
```
