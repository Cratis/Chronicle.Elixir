# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.PreparedEventTest do
  use Chronicle.AppendWireCase

  alias Chronicle.EventSequences.{PreparedEvent, Streams}

  describe "EventLog.prepare/2" do
    test "captures the owner, the serialized content and the event type", %{opts: opts} do
      [client: client] = opts
      assert {:ok, %PreparedEvent{} = prepared} = EventLog.prepare(%Event{some_value: 42}, opts)

      assert prepared.owner == {client, "namespace", "event-log"}
      assert prepared.content == ~s({"someValue":42})
      assert prepared.event == %Event{some_value: 42}
      assert prepared.event_type."Id" == "append-wire-event"
    end

    test "honors an explicit :event_sequence_id in the owner", %{opts: opts} do
      [client: client] = opts

      assert {:ok, %PreparedEvent{owner: owner}} =
               EventLog.prepare(%Event{some_value: 1}, opts ++ [event_sequence_id: "audit-log"])

      assert owner == {client, "namespace", "audit-log"}
    end
  end

  describe "EventLog.append_prepared/3" do
    test "appends the prepared content without re-serializing", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 7}, opts)

      assert :ok = EventLog.append_prepared("source", prepared, opts)

      assert %Wire.AppendRequest{Content: ~s({"someValue":7}), EventSourceId: "source"} =
               take_request()
    end

    test "sends the same wire content as an ordinary append of the same event", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 9}, opts)
      assert :ok = EventLog.append_prepared("source", prepared, opts)
      prepared_request = take_request()

      assert :ok = EventLog.append("source", %Event{some_value: 9}, opts)
      ordinary_request = take_request()

      assert prepared_request."Content" == ordinary_request."Content"
      assert prepared_request."EventType" == ordinary_request."EventType"
    end

    test "is buffered in a unit of work like an ordinary append", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 3}, opts)
      unit = UnitOfWork.begin()

      assert :ok = EventLog.append_prepared("source", prepared, opts)
      assert :ok = UnitOfWork.commit(unit)

      assert %Wire.AppendManyForEventSourcesRequest{Events: [event]} = take_request()
      assert event."Content" == ~s({"someValue":3})
    end

    test "mutating the original event struct afterward does not affect the prepared content",
         %{opts: opts} do
      event = %Event{some_value: 1}
      {:ok, prepared} = EventLog.prepare(event, opts)
      _mutated = %{event | some_value: 999}

      assert :ok = EventLog.append_prepared("source", prepared, opts)
      assert %Wire.AppendRequest{Content: ~s({"someValue":1})} = take_request()
    end

    test "rejects a prepared event appended through a different event sequence", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 1}, opts)

      assert {:error, :prepared_event_belongs_to_another_sequence} =
               EventLog.append_prepared(
                 "source",
                 prepared,
                 opts ++ [event_sequence_id: "other-sequence"]
               )
    end

    test "rejects a prepared event appended through a different namespace", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 1}, opts)

      assert {:error, :prepared_event_belongs_to_another_sequence} =
               EventLog.append_prepared(
                 "source",
                 prepared,
                 opts ++ [namespace: "other-namespace"]
               )
    end
  end

  describe "Streams.verify_content/3 with a prepared event" do
    test "verifies against the prepared content without re-serializing", %{opts: opts} do
      {:ok, prepared} = EventLog.prepare(%Event{some_value: 5}, opts)

      assert {:ok, :equal} = Streams.verify_content(3, prepared, opts)

      assert %Wire.VerifyContentRequest{Content: ~s({"someValue":5}), SequenceNumber: 3} =
               take_request()
    end
  end
end
