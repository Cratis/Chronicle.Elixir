# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.CaseTest do
  use Chronicle.Testing.Case,
    event_types: [Chronicle.Testing.CaseTest.PingEvent],
    async: true

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog

  defmodule PingEvent do
    use Chronicle.Events.EventType, id: "case-ping"
    defstruct []
  end

  test "injects a ready-to-use client into the test context", %{chronicle: client} do
    assert is_atom(client)
    :ok = EventLog.append("ping-1", %PingEvent{}, client: client)
    assert_appended(client, PingEvent, event_source_id: "ping-1")
  end
end
