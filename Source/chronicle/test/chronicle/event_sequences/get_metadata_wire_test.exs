# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.GetMetadataWireTest do
  use Chronicle.AppendWireCase

  alias Chronicle.EventSequences.Streams

  test "de-duplicates sequence numbers before sending the request", %{opts: opts} do
    assert {:ok, []} = Streams.get_metadata([1, 2, 1, 3, 2], opts)
    assert %Wire.MetadataAtRequest{SequenceNumbers: [1, 2, 3]} = take_request()
  end

  test "refuses more than 500 locators without sending a request", %{opts: opts} do
    sequence_numbers = Enum.to_list(1..501)

    assert {:error, {:too_many_event_locators, 500}} =
             Streams.get_metadata(sequence_numbers, opts)

    refute_receive {:wire_request, _}, 50
  end

  test "accepts exactly 500 distinct locators", %{opts: opts} do
    sequence_numbers = Enum.to_list(1..500)
    assert {:ok, []} = Streams.get_metadata(sequence_numbers, opts)
  end

  test "get_metadata_at/2 returns a single metadata map", %{opts: opts} do
    put_response(:metadata, [
      %Wire.EventMetadataResponse{SequenceNumber: 7, EventTypeId: "opened"}
    ])

    assert {:ok, metadata} = Streams.get_metadata_at(7, opts)
    assert metadata.sequence_number == 7
    assert metadata.event_type_id == "opened"
  end

  test "get_metadata_at/2 returns not_found when nothing comes back", %{opts: opts} do
    assert {:error, :not_found} = Streams.get_metadata_at(7, opts)
  end
end
