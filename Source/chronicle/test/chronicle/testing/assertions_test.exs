# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.AssertionsTest do
  use ExUnit.Case, async: true

  import Chronicle.Testing.Assertions
  import ExUnit.CaptureIO

  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Testing

  defmodule PingEvent do
    use Chronicle.Events.EventType, id: "assertions-ping"
    defstruct [:value]
  end

  defmodule PongEvent do
    use Chronicle.Events.EventType, id: "assertions-pong"
    defstruct []
  end

  setup do
    {:ok, client} = Testing.start_supervised_client(event_types: [PingEvent, PongEvent])
    on_exit(fn -> Testing.stop_supervised_client(client) end)
    %{client: client}
  end

  test "assert_appended matches by exact struct, by module, and by predicate", %{client: client} do
    :ok = EventLog.append("ping-1", %PingEvent{value: 1}, client: client)

    assert_appended(client, %PingEvent{value: 1}, event_source_id: "ping-1")
    assert_appended(client, PingEvent, event_source_id: "ping-1")
    assert_appended(client, fn event -> event.value == 1 end, event_source_id: "ping-1")
  end

  test "assert_appended fails with a clear message when nothing matches", %{client: client} do
    assert_raise ExUnit.AssertionError, ~r/expected an event matching/, fn ->
      assert_appended(client, PingEvent, event_source_id: "missing")
    end
  end

  test "assert_appended with :count requires an exact number of matches", %{client: client} do
    :ok = EventLog.append("ping-2", %PingEvent{value: 1}, client: client)
    :ok = EventLog.append("ping-2", %PingEvent{value: 2}, client: client)

    assert_appended(client, PingEvent, event_source_id: "ping-2", count: 2)

    assert_raise ExUnit.AssertionError, fn ->
      assert_appended(client, PingEvent, event_source_id: "ping-2", count: 1)
    end
  end

  test "refute_appended passes when nothing matches and fails otherwise", %{client: client} do
    refute_appended(client, PongEvent, event_source_id: "ping-3")

    :ok = EventLog.append("ping-3", %PongEvent{}, client: client)

    assert_raise ExUnit.AssertionError, ~r/expected no event matching/, fn ->
      refute_appended(client, PongEvent, event_source_id: "ping-3")
    end
  end

  test "assert_constraint_violation and assert_concurrency_violation flunk on a success result" do
    capture_io(:stderr, fn ->
      assert_raise ExUnit.AssertionError, fn -> assert_constraint_violation(:ok) end
      assert_raise ExUnit.AssertionError, fn -> assert_concurrency_violation(:ok) end
    end)
  end
end
