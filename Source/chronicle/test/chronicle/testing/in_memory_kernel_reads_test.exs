# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.InMemoryKernelReadsTest do
  use Chronicle.Testing.Case, event_types: [Chronicle.Testing.InMemoryKernelReadsTest.Opened]

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Chronicle.EventSequences.EventLog

  defmodule Opened do
    use Chronicle.Events.EventType, id: "in-memory-reads-opened"
    defstruct owner: ""
  end

  # protobuf warns about a "non-struct cast" (on stderr or through Logger, depending on the
  # version) when a response is built from plain maps.
  defp reads(client) do
    :ok = EventLog.append("acct-1", %Opened{owner: "ada"}, client: client)
    test = self()

    capture_io(:stderr, fn ->
      log =
        capture_log([level: :warning], fn ->
          assert {:ok, [from_number]} =
                   EventLog.get_from_sequence_number(0,
                     client: client,
                     event_source_id: "acct-1"
                   )

          assert {:ok, [for_source]} = EventLog.get_for_event_source("acct-1", client: client)

          send(test, {:read, from_number, for_source})
        end)

      send(test, {:log, log})
    end)
  end

  test "reading through get_from_sequence_number and get_for_event_source does not warn",
       %{chronicle: client} do
    stderr = reads(client)
    assert_received {:log, log}

    for output <- [stderr, log] do
      refute output =~ "non-struct"
      refute output =~ "protobuf"
    end

    assert_received {:read, from_number, for_source}
    assert from_number."Context"."EventSourceId" == "acct-1"
    assert from_number."Context"."EventType"."Id" == "in-memory-reads-opened"
    assert Jason.decode!(for_source."Content") == %{"owner" => "ada"}
  end
end
