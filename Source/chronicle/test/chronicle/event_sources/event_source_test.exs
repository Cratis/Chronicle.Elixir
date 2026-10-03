# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.EventSourceTest do
  use Chronicle.AppendWireCase, async: false

  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.EventSources
  alias Chronicle.EventSources.{ConcurrencyDimensions, DuplicateEventSourceName, EventStream}
  alias Cratis.Chronicle.Contracts.EventSources.RegisterEventSourcesRequest

  defmodule AccountEventSource do
    use Chronicle.EventSources.EventSource,
      name: "Account",
      description: "A bank account",
      concurrency: [:event_source_id]

    stream("Transactions",
      description: "Money movements",
      concurrency: [:event_source_id, :event_stream_id]
    )

    stream("Audit")
  end

  defmodule OrderEventSource do
    use Chronicle.EventSources.EventSource
  end

  defmodule OtherAccount do
    use Chronicle.EventSources.EventSource, name: "Account"
  end

  defmodule Unregistered do
    use Chronicle.EventSources.EventSource, name: "Unregistered"
  end

  defp register_sources(modules) do
    config = :persistent_term.get({Chronicle.Client, self()})
    :persistent_term.put({Chronicle.Client, self()}, Map.put(config, :event_sources, modules))
  end

  defp requests(acc \\ []) do
    receive do
      {:wire_request, %Cratis.Chronicle.Contracts.Clients.CompatibilityRequest{}} -> requests(acc)
      {:wire_request, request} -> requests([request | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  describe "definitions" do
    test "describe name, description, dimensions and streams" do
      definition = AccountEventSource.__chronicle_event_source__(:definition)

      assert definition.name == "Account"
      assert definition.description == "A bank account"
      assert definition.concurrency == [:event_source_id]

      assert [
               %EventStream{
                 name: "Transactions",
                 concurrency: [:event_source_id, :event_stream_id]
               },
               %EventStream{name: "Audit", description: "", concurrency: []}
             ] = definition.streams
    end

    test "name defaults to the module name without the EventSource suffix" do
      assert OrderEventSource.__chronicle_event_source__(:name) == "Order"
    end

    test "duplicate stream names are rejected at compile time" do
      assert_raise Chronicle.EventSources.DuplicateEventStreamName, ~r/"Dup"/, fn ->
        Code.compile_string("""
        defmodule Chronicle.EventSources.EventSourceTest.DupStreams do
          use Chronicle.EventSources.EventSource
          stream "Dup"
          stream "Dup"
        end
        """)
      end
    end

    test "duplicate source names are rejected" do
      assert_raise DuplicateEventSourceName, ~r/"Account"/, fn ->
        EventSources.describe!([AccountEventSource, OtherAccount])
      end
    end

    test "dimensions normalize to wire flags" do
      assert ConcurrencyDimensions.to_flags([:event_stream_id, :event_source_id]) == 9
      assert ConcurrencyDimensions.normalize(6) == [:event_source_type, :event_stream_type]
      assert ConcurrencyDimensions.to_flags(:none) == 0
      assert_raise ArgumentError, fn -> ConcurrencyDimensions.normalize([:nope]) end
    end

    test "are discovered by the artifact scan" do
      assert AccountEventSource in Chronicle.Artifacts.discover_loaded().event_sources
    end
  end

  describe "registration" do
    test "sends every definition, with streams and flags", %{connection: connection} do
      {:ok, channel} = Chronicle.Connections.Connection.channel(connection)

      assert :ok = EventSources.register(channel, "store", [AccountEventSource, OrderEventSource])

      assert [%RegisterEventSourcesRequest{EventStore: "store", Sources: [account, order]}] =
               requests()

      assert account."Name" == "Account"
      assert account."Owner" == :Client
      assert account."Concurrency" == :EventSourceId

      assert [
               %{Name: "Transactions", Concurrency: 9},
               %{Name: "Audit", Concurrency: :CONCURRENCY_DIMENSIONS_None}
             ] = account."Streams"

      assert order."Name" == "Order"
    end

    test "does nothing when there are no definitions", %{connection: connection} do
      {:ok, channel} = Chronicle.Connections.Connection.channel(connection)
      assert :ok = EventSources.register(channel, "store", [])
      assert requests() == []
    end
  end

  describe "append through a definition" do
    setup do
      register_sources([AccountEventSource, OrderEventSource])
      put_response(:tail_sequence_number, 4)
    end

    test "routes by the definition and records the EventSource", %{opts: opts} do
      assert :ok =
               append(:single, opts ++ [event_source: AccountEventSource, event_stream: "Audit"])

      # Audit declares none, so it inherits the source dimensions (a tail read).
      assert [%Wire.TailSequenceNumberRequest{}, %Wire.AppendRequest{} = request] = requests()
      assert request."EventSource" == "Account"
      assert request."EventSourceType" == "Account"
      assert request."EventStreamType" == "Audit"
    end

    test "accepts the source by name and defaults the stream to All", %{opts: opts} do
      assert :ok = append(:single, opts ++ [event_source: "Order"])
      assert [%Wire.AppendRequest{EventSource: "Order", EventStreamType: "All"}] = requests()
    end

    test "legacy appends do not claim registered-source metadata", %{opts: opts} do
      assert :ok = append(:single, opts)
      assert [%Wire.AppendRequest{} = request] = requests()
      assert request."EventSource" == ""
      assert request."EventSourceType" == ""
      assert request."EventStreamType" == ""
    end

    test "append-many routes every event and stays one request", %{opts: opts} do
      assert :ok = append(:ordinary, opts ++ [event_source: "Order"])
      assert [%Wire.AppendManyForEventSourcesRequest{Events: [event]}] = requests()
      assert event."EventSource" == "Order"
      assert event."EventSourceType" == "Order"
    end

    test "transactions resolve at commit", %{opts: opts} do
      assert :ok = append(:transaction, opts ++ [event_source: "Order"])

      assert [%Wire.AppendManyForEventSourcesRequest{Events: [%{EventSource: "Order"}]}] =
               requests()
    end

    test "per-event routing wins in a mixed-source batch", %{opts: opts} do
      events = [
        %EventForEventSourceId{
          event_source_id: "a",
          event: %Event{},
          event_source: AccountEventSource,
          event_stream: "Audit"
        },
        %EventForEventSourceId{event_source_id: "b", event: %Event{}, event_source: "Order"},
        %EventForEventSourceId{event_source_id: "c", event: %Event{}}
      ]

      assert :ok =
               EventLog.append_many_for_event_sources(
                 events,
                 opts ++ [event_source: "Order", event_stream: nil]
               )

      assert [%Wire.TailSequenceNumberRequest{}, %{Events: [first, second, third]}] = requests()
      assert {first."EventSource", first."EventStreamType"} == {"Account", "Audit"}
      assert {second."EventSource", second."EventStreamType"} == {"Order", "All"}
      # Entries that name no source take the batch-level default.
      assert third."EventSource" == "Order"
    end

    test "batch routing defaults leave other entries untouched when none is given", %{opts: opts} do
      events = [%EventForEventSourceId{event_source_id: "a", event: %Event{}}]
      assert :ok = EventLog.append_many_for_event_sources(events, opts)
      assert [%{Events: [%{EventSource: "", EventSourceType: ""}]}] = requests()
    end
  end

  describe "routing errors" do
    setup do
      register_sources([AccountEventSource])
    end

    test "unknown source", %{opts: opts} do
      assert {:error, {:unknown_event_source, "Nope"}} =
               append(:single, opts ++ [event_source: "Nope"])

      assert {:error, {:unknown_event_source, Unregistered}} =
               append(:single, opts ++ [event_source: Unregistered])

      assert requests() == []
    end

    test "stream not declared by the source", %{opts: opts} do
      assert {:error, {:event_stream_does_not_belong_to_event_source, "Account", "Nope"}} =
               append(:single, opts ++ [event_source: "Account", event_stream: "Nope"])
    end

    test "contradicting explicit routing", %{opts: opts} do
      assert {:error,
              {:event_routing_contradicts_event_source, "Account", :event_source_type, "Account",
               "Other"}} =
               append(:single, opts ++ [event_source: "Account", event_source_type: "Other"])

      assert {:error,
              {:event_routing_contradicts_event_source, "Account", :event_stream_type, "Audit",
               "Transactions"}} =
               append(
                 :single,
                 opts ++
                   [
                     event_source: "Account",
                     event_stream: "Audit",
                     event_stream_type: "Transactions"
                   ]
               )
    end

    test "matching and unspecified explicit routing is accepted", %{opts: opts} do
      put_response(:tail_sequence_number, 1)

      assert :ok =
               append(
                 :single,
                 opts ++
                   [
                     event_source: "Account",
                     event_source_type: "Account",
                     event_stream_type: "All"
                   ]
               )
    end

    test "a stream without a source", %{opts: opts} do
      assert {:error, {:event_stream_without_event_source, "Audit"}} =
               append(:single, opts ++ [event_stream: "Audit"])
    end

    test "append-many is atomic: one bad entry sends nothing", %{opts: opts} do
      events = [
        %EventForEventSourceId{event_source_id: "a", event: %Event{}, event_source: "Account"},
        %EventForEventSourceId{event_source_id: "b", event: %Event{}, event_source: "Nope"}
      ]

      assert {:error, {:unknown_event_source, "Nope"}} =
               EventLog.append_many_for_event_sources(events, opts)

      assert requests() == []
    end
  end

  describe "concurrency dimensions" do
    setup do
      register_sources([AccountEventSource, OrderEventSource])
      put_response(:tail_sequence_number, 4)
    end

    test "derive the scope from the source dimensions", %{opts: opts} do
      assert :ok = append(:single, opts ++ [event_source: "Account"])

      assert [%Wire.TailSequenceNumberRequest{} = tail, %Wire.AppendRequest{} = request] =
               requests()

      assert tail."EventSourceId" == "source"
      assert tail."EventStreamType" == ""
      assert request."ConcurrencyScope"."SequenceNumber" == 4
      assert request."ConcurrencyScope"."EventSourceId"
    end

    test "stream dimensions replace the source's and narrow the tail read", %{opts: opts} do
      assert :ok =
               append(
                 :single,
                 opts ++
                   [event_source: "Account", event_stream: "Transactions", event_stream_id: "t-1"]
               )

      assert [%Wire.TailSequenceNumberRequest{} = tail, %Wire.AppendRequest{} = request] =
               requests()

      assert tail."EventStreamId" == "t-1"
      assert tail."EventStreamType" == ""
      assert request."ConcurrencyScope"."EventStreamId" == "t-1"
    end

    test "an explicit scope wins and nothing is read", %{opts: opts} do
      assert :ok =
               append(
                 :single,
                 opts ++
                   [
                     event_source: "Account",
                     concurrency_scope: ConcurrencyScope.for_event_source(9)
                   ]
               )

      assert [%Wire.AppendRequest{} = request] = requests()
      assert request."ConcurrencyScope"."SequenceNumber" == 9
    end

    test "an explicit none scope also wins", %{opts: opts} do
      assert :ok =
               append(
                 :single,
                 opts ++ [event_source: "Account", concurrency_scope: ConcurrencyScope.none()]
               )

      assert [%Wire.AppendRequest{} = request] = requests()
      assert request."ConcurrencyScope"."SequenceNumber" == 18_446_744_073_709_551_615
    end

    test "sources without dimensions send no scope", %{opts: opts} do
      assert :ok = append(:single, opts ++ [event_source: "Order"])
      assert [%Wire.AppendRequest{ConcurrencyScope: nil}] = requests()
    end

    test "append-many derives one scope per distinct source id", %{opts: opts} do
      events = [
        %EventForEventSourceId{event_source_id: "a", event: %Event{}, event_source: "Account"},
        %EventForEventSourceId{event_source_id: "a", event: %Event{}, event_source: "Account"},
        %EventForEventSourceId{
          event_source_id: "b",
          event: %Event{},
          event_source: "Account",
          concurrency_scope: ConcurrencyScope.new(2)
        }
      ]

      assert :ok = EventLog.append_many_for_event_sources(events, opts)

      assert [
               %Wire.TailSequenceNumberRequest{EventSourceId: "a"},
               %Wire.AppendManyForEventSourcesRequest{} = request
             ] = requests()

      assert [
               %{EventSourceId: "a", Scope: %{SequenceNumber: 4}},
               %{EventSourceId: "b", Scope: %{SequenceNumber: 2}}
             ] =
               request."ConcurrencyScopes"
    end
  end

  describe "event context" do
    for handler <- [Chronicle.Reactors.Handler, Chronicle.Reducers.Handler] do
      test "#{inspect(handler)} exposes the event source of a registered-source event" do
        context = unquote(handler).build_context(%{EventSource: "Account", EventSourceId: "a"})
        assert context.event_source == "Account"
        assert context.event_source_id == "a"
      end

      test "#{inspect(handler)} uses nil, not a fabricated name, for old or unset events" do
        assert unquote(handler).build_context(%{EventSourceId: "a"}).event_source == nil

        assert unquote(handler).build_context(%{EventSource: "", EventSourceId: "a"}).event_source ==
                 nil
      end
    end
  end
end
