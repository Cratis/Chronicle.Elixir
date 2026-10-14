# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.UnknownEventTypeTest do
  use Chronicle.AppendWireCase

  alias Chronicle.EventSequences.Streams

  defmodule NotAnEventType do
    defstruct [:value]
  end

  defp refute_request_sent do
    receive do
      {:wire_request, %Cratis.Chronicle.Contracts.Clients.CompatibilityRequest{}} ->
        refute_request_sent()

      {:wire_request, other} ->
        flunk("expected no request to be sent, got: #{inspect(other)}")
    after
      50 -> :ok
    end
  end

  describe "EventLog.append/3" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append("source", %NotAnEventType{}, opts)

      refute_request_sent()
    end

    test "returns the error when buffered in a unit of work", %{opts: opts} do
      unit = UnitOfWork.begin()

      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append("source", %NotAnEventType{}, opts)

      UnitOfWork.rollback(unit)
      refute_request_sent()
    end
  end

  describe "EventLog.append_many/3" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_many("source", [%Event{}, %NotAnEventType{}], opts)

      refute_request_sent()
    end

    test "returns the error when buffered in a unit of work, before any valid event is sent", %{
      opts: opts
    } do
      unit = UnitOfWork.begin()

      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_many("source", [%NotAnEventType{}, %Event{}], opts)

      UnitOfWork.rollback(unit)
      refute_request_sent()
    end
  end

  describe "EventLog.append_with_result/3" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_with_result("source", %NotAnEventType{}, opts)

      refute_request_sent()
    end
  end

  describe "EventLog.append_many_with_result/3" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_many_with_result("source", [%NotAnEventType{}], opts)

      refute_request_sent()
    end
  end

  describe "EventLog.append_many_for_event_sources/2" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      entry = %EventForEventSourceId{event_source_id: "source", event: %NotAnEventType{}}

      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_many_for_event_sources([entry], opts)

      refute_request_sent()
    end

    test "returns the error when buffered in a unit of work", %{opts: opts} do
      unit = UnitOfWork.begin()
      entry = %EventForEventSourceId{event_source_id: "source", event: %NotAnEventType{}}

      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.append_many_for_event_sources([entry], opts)

      UnitOfWork.rollback(unit)
      refute_request_sent()
    end
  end

  describe "EventLog.prepare/2" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               EventLog.prepare(%NotAnEventType{}, opts)

      refute_request_sent()
    end
  end

  describe "Streams.verify_content/3" do
    test "returns a structured error and sends nothing", %{opts: opts} do
      assert {:error, {:unknown_event_type, NotAnEventType}} =
               Streams.verify_content(1, %NotAnEventType{}, opts)

      refute_request_sent()
    end
  end
end
