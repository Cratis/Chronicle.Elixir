```elixir
defmodule MyApp.Events.LegacyOrderPlaced do
  use Chronicle.Events.EventType, id: "legacy-order-placed"

  defstruct order_number: ""
end

defmodule MyApp.OrderMigration do
  alias Chronicle.EventSequences.EventForEventSourceId

  def run(batches) do
    {:ok, session} = Chronicle.Imports.begin(max_chunks_in_flight: 4)
    IO.puts("Importing as #{session.import_id}")

    session =
      Enum.reduce(batches, session, fn batch, session ->
        {:ok, session} = Chronicle.Imports.add(session, Enum.map(batch, &to_event/1))
        session
      end)

    Chronicle.Imports.complete(session)
  end

  defp to_event({order_id, number}) do
    %EventForEventSourceId{
      event_source_id: order_id,
      event: %MyApp.Events.LegacyOrderPlaced{order_number: number}
    }
  end
end
```
