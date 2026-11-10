# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EntryGenerationTest do
  use Chronicle.AppendWireCase, async: false

  test "an entry's generation is the generation its event is appended under", %{opts: opts} do
    entry = %EventForEventSourceId{
      event_source_id: "source",
      event: %Event{some_value: 1},
      generation: 3
    }

    EventLog.append_many_for_event_sources([entry], opts)

    assert %Wire.AppendManyForEventSourcesRequest{Events: [%{EventType: %{Generation: 3}}]} =
             take_request()
  end

  test "without one the event's declared generation is used", %{opts: opts} do
    entry = %EventForEventSourceId{event_source_id: "source", event: %Event{some_value: 1}}
    EventLog.append_many_for_event_sources([entry], opts)

    assert %Wire.AppendManyForEventSourcesRequest{Events: [%{EventType: %{Generation: 1}}]} =
             take_request()
  end
end
