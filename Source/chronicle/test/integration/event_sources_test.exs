# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel (19.30.0 or newer). Opt in by pointing
# CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel, for example
# chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000
# and run `mix test --include integration`.
defmodule Chronicle.Integration.EventSourcesTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.EventSequences.{EventForEventSourceId, EventLog}
  alias Chronicle.Events.ConcurrencyScope

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "it-account-opened"
    defstruct owner: ""
  end

  defmodule AccountEventSource do
    use Chronicle.EventSources.EventSource, name: "ItAccount", concurrency: [:event_source_id]
    stream("Transactions", description: "Money movements")
  end

  defmodule Seen do
    use Chronicle.Reactors.Reactor
    @handles AccountOpened
    def handle(_event, context) do
      send(:event_source_it, {:seen, context.event_source})
      :ok
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "eventsource-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :event_source_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store: "#{prefix}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [AccountOpened],
        event_sources: [AccountEventSource],
        reactors: [Seen]
      )

    wait_for_registration()
    :ok
  end

  setup do
    Process.register(self(), :event_source_it)

    on_exit(fn ->
      if Process.whereis(:event_source_it), do: Process.unregister(:event_source_it)
    end)
  end

  defp wait_for_registration do
    lifecycle = Chronicle.Connections.Lifecycle.name_for(:event_source_it_client)
    :ok = Chronicle.Connections.Lifecycle.wait_until(lifecycle, :registered, 60_000)
  end

  @opts [client: :event_source_it_client]

  test "append through a definition round-trips the event source metadata" do
    assert :ok =
             EventLog.append(
               "acc-1",
               %AccountOpened{owner: "Ada"},
               @opts ++ [event_source: AccountEventSource, event_stream: "Transactions"]
             )

    assert {:ok, [event]} = EventLog.get_for_event_source("acc-1", @opts)
    assert event."Context"."EventSource" == "ItAccount"
    assert event."Context"."EventSourceType" == "ItAccount"
    assert event."Context"."EventStreamType" == "Transactions"
    assert_receive {:seen, "ItAccount"}, 10_000
  end

  test "legacy appends carry no event source" do
    assert :ok = EventLog.append("legacy-1", %AccountOpened{owner: "Bob"}, @opts)
    assert {:ok, [event]} = EventLog.get_for_event_source("legacy-1", @opts)
    assert event."Context"."EventSource" in [nil, ""]
  end

  test "rejected routing leaves the whole append-many unwritten" do
    events = [
      %EventForEventSourceId{
        event_source_id: "acc-2",
        event: %AccountOpened{},
        event_source: AccountEventSource
      },
      %EventForEventSourceId{
        event_source_id: "acc-3",
        event: %AccountOpened{},
        event_source: "Missing"
      }
    ]

    assert {:error, {:unknown_event_source, "Missing"}} =
             EventLog.append_many_for_event_sources(events, @opts)

    assert {:ok, []} = EventLog.get_for_event_source("acc-2", @opts)
  end

  test "definition dimensions detect a concurrent append" do
    opts = @opts ++ [event_source: AccountEventSource]
    assert :ok = EventLog.append("acc-4", %AccountOpened{}, opts)
    stale = ConcurrencyScope.for_event_source(0, event_source_type: "ItAccount")

    assert {:error, _} =
             EventLog.append("acc-4", %AccountOpened{}, opts ++ [concurrency_scope: stale])

    assert :ok = EventLog.append("acc-4", %AccountOpened{}, opts)
  end
end
