```elixir
defmodule MyApp.Events.TestingCollectionScopeItemRegistered do
  use Chronicle.Events.EventType, id: "testing-collection-scope-item-registered"

  defstruct [:name]
end

defmodule MyApp.TestingCollectionScopeTest do
  # `Chronicle.Testing.Case` is the one-time per-test-module setup: every test
  # gets its own in-memory kernel and client (so there is no shared fixture to
  # bring up once), put in the context as `:chronicle`, and torn down
  # automatically. There is no separate collector to start or dispose —
  # `Chronicle.Testing.appended_events/2` reads straight from the client's own
  # in-memory event log, scoped to that client alone.
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingCollectionScopeItemRegistered]

  alias MyApp.Events.TestingCollectionScopeItemRegistered

  test "appending is captured for this client only", %{chronicle: client} do
    event_source_id = "item-#{System.unique_integer([:positive])}"

    :ok =
      Chronicle.EventSequences.EventLog.append(
        event_source_id,
        %TestingCollectionScopeItemRegistered{name: "Widget"},
        client: client
      )

    assert [%TestingCollectionScopeItemRegistered{name: "Widget"}] =
             client |> Chronicle.Testing.appended_events(event_source_id) |> Enum.map(& &1.event)
  end
end
```
