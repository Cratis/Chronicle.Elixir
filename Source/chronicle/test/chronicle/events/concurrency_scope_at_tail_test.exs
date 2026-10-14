# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConcurrencyScopeAtTailTest do
  use Chronicle.AppendWireCase

  alias Chronicle.Events.ConcurrencyScope

  test "reads the tail and returns a scope expecting it", %{opts: opts} do
    put_response(:tail_sequence_number, 11)

    assert {:ok, scope} = ConcurrencyScope.at_tail("source", opts)

    assert scope == ConcurrencyScope.for_event_source(11)
    assert %Wire.TailSequenceNumberRequest{EventSourceId: "source"} = take_request()
  end

  test "narrows the tail read and the returned scope the same way", %{opts: opts} do
    put_response(:tail_sequence_number, 4)

    assert {:ok, scope} =
             ConcurrencyScope.at_tail(
               "source",
               opts ++ [event_stream_type: "Transactions", event_stream_id: "2024"]
             )

    assert scope.event_stream_type == "Transactions"
    assert scope.event_stream_id == "2024"

    assert %Wire.TailSequenceNumberRequest{
             EventStreamType: "Transactions",
             EventStreamId: "2024"
           } = take_request()
  end
end
