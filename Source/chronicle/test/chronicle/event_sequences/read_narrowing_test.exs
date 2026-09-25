# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ReadNarrowingTest do
  @moduledoc """
  The event source type was read from the options and then dropped before the request was built, so a
  caller narrowing by it got every source type back with no way to tell. The kernel gained the field in
  18.5.0. See Cratis/Chronicle#4049.

  An omitted dimension must stay empty rather than becoming the legacy `Default` route, which is what
  would hide every event the kernel routed for an append that named no route.
  """
  use Chronicle.AppendWireCase, async: false

  defp read(opts), do: EventLog.get_for_event_source("source", opts)

  describe "get_for_event_source/2" do
    test "sends the event source type it was given", %{opts: opts} do
      read(opts ++ [event_source_type: "Order"])
      request = take_request()

      assert request."EventSourceType" == "Order"
    end

    test "leaves every dimension unnarrowed when none is given", %{opts: opts} do
      read(opts)
      request = take_request()

      assert [request."EventSourceType", request."EventStreamType", request."EventStreamId"] ==
               ["", "", ""]
    end

    test "sends every dimension unchanged when all are given", %{opts: opts} do
      read(
        opts ++ [event_source_type: "Order", event_stream_type: "All", event_stream_id: "2024"]
      )

      request = take_request()

      assert [request."EventSourceType", request."EventStreamType", request."EventStreamId"] ==
               ["Order", "All", "2024"]
    end

    test "survives the protobuf round trip on the event source type", %{opts: opts} do
      read(opts ++ [event_source_type: " Account "])
      request = take_request()

      assert request."EventSourceType" == " Account "
    end
  end

  describe "get_tail_sequence_number/2" do
    test "leaves the source and stream type unnarrowed when none is given", %{opts: opts} do
      EventLog.get_tail_sequence_number("source", opts)
      request = take_request()

      assert [request."EventSourceType", request."EventStreamType", request."EventStreamId"] ==
               ["", "", ""]
    end

    test "sends the source and stream type it was given", %{opts: opts} do
      EventLog.get_tail_sequence_number(
        "source",
        opts ++ [event_source_type: "Order", event_stream_type: "Audit"]
      )

      request = take_request()

      assert [request."EventSourceType", request."EventStreamType"] == ["Order", "Audit"]
    end

    test "returns the sequence number from the query result", %{opts: opts} do
      put_response(:tail_sequence_number, 41)

      assert EventLog.get_tail_sequence_number("source", opts) == {:ok, 41}
    end
  end

  describe "has_events_for?/2" do
    test "reads the answer from the query result envelope", %{opts: opts} do
      put_response(:has_events, true)

      assert EventLog.has_events_for?("source", opts) == {:ok, true}
    end

    test "reports false when the event source has no events", %{opts: opts} do
      put_response(:has_events, false)

      assert EventLog.has_events_for?("source", opts) == {:ok, false}
    end
  end
end
