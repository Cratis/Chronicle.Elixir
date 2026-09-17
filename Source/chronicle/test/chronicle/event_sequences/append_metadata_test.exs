# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.AppendMetadataTest do
  use Chronicle.AppendWireCase, async: false

  alias Chronicle.Auditing.{CausationEntry, CausationType}
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.Identity

  @routes [:event_source_type, :event_stream_type, :event_stream_id]
  @occurred ~U[2024-03-02 01:02:03.456789Z]
  @correlation "00112233-4455-6677-8899-aabbccddeeff"

  for path <- [:single, :ordinary, :rich, :transaction],
      {name, values, expected} <- [
        {:omitted, [], ["", "", ""]},
        {nil, [nil, nil, nil], ["", "", ""]},
        {:empty, ["", "", ""], ["", "", ""]},
        {:mixed, [nil, "Explicit", ""], ["", "Explicit", ""]},
        {:explicit, ["Account", " Order ", "2024"], ["Account", " Order ", "2024"]},
        {:legacy, ["Default", "All", "Default"], ["Default", "All", "Default"]}
      ] do
    test "#{path} preserves #{name} routing after protobuf round trip", %{opts: opts} do
      routes = Enum.zip(@routes, unquote(values))
      assert :ok = append(unquote(path), opts ++ routes)
      request = take_request()
      event = entry(request)

      assert [event."EventSourceType", event."EventStreamType", event."EventStreamId"] ==
               unquote(expected)

      assert event."EventSourceId" == "source"
      assert event."Occurred" == nil
      assert event."Content" == ~s({"someValue":42})
      assert event."EventType"."Id" == "append-wire-event"
      assert request."EventStore" == "store"
      assert request."Namespace" == "namespace"
      assert request."EventSequenceId" == "event-log"
      assert no_scope?(request)
    end
  end

  for path <- [:single, :ordinary, :rich, :transaction] do
    test "#{path} preserves explicit metadata and independent scope", %{opts: opts} do
      scope =
        ConcurrencyScope.for_event_source(7,
          event_source_type: "FilterSource",
          event_stream_type: "FilterStream",
          event_stream_id: "FilterId",
          event_types: [Event]
        )

      identity = Identity.new("subject", "Actor", "actor")
      cause = CausationEntry.new(CausationType.append_event(), %{reason: "test"})

      options =
        opts ++
          [
            namespace: "override",
            event_sequence_id: "audit",
            correlation_id: @correlation,
            event_source_type: "RouteSource",
            event_stream_type: "RouteStream",
            event_stream_id: "RouteId",
            tags: ["first", "second"],
            subject: "person",
            occurred: @occurred,
            identity: identity,
            causation: [cause],
            concurrency_scope: scope
          ]

      assert :ok = append(unquote(path), options)
      request = take_request()
      event = entry(request)
      assert event."Tags" == ["first", "second"]
      assert event."Subject" == "person"
      assert event."Occurred"."Value" == DateTime.to_iso8601(@occurred)
      assert request."Namespace" == "override"
      assert request."EventSequenceId" == "audit"
      assert request."CausedBy"."Subject" == "subject"
      assert request."CausedBy"."Name" == "Actor"
      assert request."CausedBy"."UserName" == "actor"
      assert request."CorrelationId".lo == 0x6677445500112233
      assert request."CorrelationId".hi == 0xFFEEDDCCBBAA9988

      if unquote(path) != :rich do
        assert hd(request."Causation")."Properties" == %{"reason" => "test"}
        assert hd(request."Causation")."Occurred"."Value" == DateTime.to_iso8601(cause.occurred)
      end

      wire_scope = scope(request)
      assert wire_scope."SequenceNumber" == 7
      assert wire_scope."EventSourceId"
      assert wire_scope."EventSourceType" == "FilterSource"
      assert wire_scope."EventStreamType" == "FilterStream"
      assert wire_scope."EventStreamId" == "FilterId"
      assert Enum.map(wire_scope."EventTypes", & &1."Id") == ["append-wire-event"]
      assert event."EventStreamId" == "RouteId"
    end

    for sequence <- [0, 9, 18_446_744_073_709_551_614, 18_446_744_073_709_551_615] do
      test "#{path} preserves explicit scope sequence #{sequence}", %{opts: opts} do
        assert :ok =
                 append(
                   unquote(path),
                   opts ++ [concurrency_scope: ConcurrencyScope.new(unquote(sequence))]
                 )

        wire_scope = take_request() |> scope()
        assert wire_scope."SequenceNumber" == unquote(sequence)
        refute wire_scope."EventSourceId"
        assert wire_scope."EventSourceType" == ""
        assert wire_scope."EventStreamType" == ""
        assert wire_scope."EventStreamId" == ""
      end
    end
  end

  for path <- [:single, :ordinary, :rich, :transaction] do
    test "#{path} preserves the explicit none scope policy", %{opts: opts} do
      assert :ok = append(unquote(path), opts ++ [concurrency_scope: ConcurrencyScope.none()])
      wire_scope = take_request() |> scope()
      assert wire_scope."SequenceNumber" == 18_446_744_073_709_551_615
      refute wire_scope."EventSourceId"
      assert wire_scope."EventSourceType" == ""
      assert wire_scope."EventStreamType" == ""
      assert wire_scope."EventStreamId" == ""
      assert wire_scope."EventTypes" == []
    end

    test "#{path} leaves explicit nil time and scope omitted", %{opts: opts} do
      assert :ok = append(unquote(path), opts ++ [occurred: nil, concurrency_scope: nil])
      request = take_request()
      assert entry(request)."Occurred" == nil
      assert no_scope?(request)
    end
  end

  test "rich transaction keeps entry metadata and first entry causation", %{opts: opts} do
    cause = CausationEntry.new(CausationType.append_event(), %{transaction: "entry"})
    unit = UnitOfWork.begin(correlation_id: @correlation)

    events = [
      %EventForEventSourceId{
        event_source_id: "one",
        event: %Event{},
        event_stream_id: "entry",
        occurred: @occurred,
        tags: ["tag"],
        subject: "person",
        causation: [cause],
        identity: Identity.new("entry", "Entry"),
        concurrency_scope: ConcurrencyScope.new(0)
      },
      %EventForEventSourceId{event_source_id: "two", event: %Event{}}
    ]

    assert :ok = EventLog.append_many_for_event_sources(events, opts)
    assert :ok = UnitOfWork.commit(unit)
    request = take_request()
    [first, second] = request."Events"
    assert first."EventStreamId" == "entry"
    assert first."Occurred"."Value" == DateTime.to_iso8601(@occurred)
    assert first."Tags" == ["tag"]
    assert first."Subject" == "person"
    assert second."Occurred" == nil
    assert second."EventStreamId" == ""
    assert request."CausedBy"."Subject" == "entry"
    assert hd(request."Causation")."Properties" == %{"transaction" => "entry"}
    assert [%{EventSourceId: "one", Scope: %{SequenceNumber: 0}}] = request."ConcurrencyScopes"
    assert request."CorrelationId".lo == 0x6677445500112233
  end

  test "ordinary batch preserves every entry in order", %{opts: opts} do
    assert :ok =
             EventLog.append_many(
               "source",
               [%Event{some_value: 1}, %Event{some_value: 2}],
               opts ++ [tags: ["batch"], occurred: @occurred]
             )

    assert %Wire.AppendManyForEventSourcesRequest{Events: events} = take_request()
    assert Enum.map(events, & &1."Content") == [~s({"someValue":1}), ~s({"someValue":2})]

    assert Enum.all?(
             events,
             &(&1."Tags" == ["batch"] and &1."Occurred"."Value" == DateTime.to_iso8601(@occurred))
           )
  end

  test "rich scope map omits unchecked sources and first declared scope wins", %{opts: opts} do
    events = [
      %EventForEventSourceId{event_source_id: "unchecked", event: %Event{}},
      %EventForEventSourceId{
        event_source_id: "checked",
        event: %Event{},
        concurrency_scope: ConcurrencyScope.none()
      },
      %EventForEventSourceId{
        event_source_id: "checked",
        event: %Event{},
        concurrency_scope: ConcurrencyScope.new(2)
      }
    ]

    assert :ok = EventLog.append_many_for_event_sources(events, opts)

    assert [%{EventSourceId: "checked", Scope: %{SequenceNumber: 18_446_744_073_709_551_615}}] =
             take_request()."ConcurrencyScopes"
  end

  test "rich entry routing and identity win while explicit batch causation is retained", %{
    opts: opts
  } do
    cause = CausationEntry.new(CausationType.append_many_events(), %{batch: "yes"})

    events = [
      %EventForEventSourceId{
        event_source_id: "one",
        event: %Event{},
        event_stream_id: "entry",
        tags: ["entry"],
        identity: Identity.new("entry", "Entry")
      }
    ]

    assert :ok =
             EventLog.append_many_for_event_sources(
               events,
               opts ++
                 [
                   event_stream_id: "option",
                   tags: ["option"],
                   identity: Identity.new("option", "Option"),
                   causation: [cause]
                 ]
             )

    request = take_request()
    assert hd(request."Events")."EventStreamId" == "entry"
    assert hd(request."Events")."Tags" == ["entry"]
    assert request."CausedBy"."Subject" == "entry"
    assert hd(request."Causation")."Properties" == %{"batch" => "yes"}
  end

  test "empty ordinary and rich batches perform no compatibility or append calls" do
    assert :ok = EventLog.append_many("source", [])
    assert :ok = EventLog.append_many_for_event_sources([])
    unit = UnitOfWork.begin()
    assert :ok = EventLog.append_many("source", [])
    assert :ok = EventLog.append_many_for_event_sources([])
    assert UnitOfWork.get_events(unit) == []
    assert :ok = UnitOfWork.commit(unit)
    refute_received {:wire_request, _}
  end

  defp entry(%Wire.AppendRequest{} = request), do: request
  defp entry(%Wire.AppendManyForEventSourcesRequest{Events: [event]}), do: event
  defp scope(%Wire.AppendRequest{ConcurrencyScope: scope}), do: scope

  defp scope(%Wire.AppendManyForEventSourcesRequest{ConcurrencyScopes: [%{Scope: scope}]}),
    do: scope

  defp no_scope?(%Wire.AppendRequest{ConcurrencyScope: scope}), do: is_nil(scope)

  defp no_scope?(%Wire.AppendManyForEventSourcesRequest{ConcurrencyScopes: scopes}),
    do: scopes == []
end
