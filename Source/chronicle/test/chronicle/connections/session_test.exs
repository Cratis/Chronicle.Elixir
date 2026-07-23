# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.SessionTest.FakeConnection do
  @moduledoc false

  # Stands in for `Chronicle.Connections.Connection`: hands out a channel that
  # cannot carry a real gRPC call and reports reconnect requests to the test.

  use GenServer

  def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

  @impl true
  def init(test_pid), do: {:ok, test_pid}

  @impl true
  def handle_call(:channel, _from, test_pid), do: {:reply, {:ok, %{fake: true}}, test_pid}

  @impl true
  def handle_cast(:reconnect, test_pid) do
    send(test_pid, :reconnect_requested)
    {:noreply, test_pid}
  end
end

defmodule Chronicle.Connections.SessionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{Lifecycle, Session}
  alias Chronicle.Connections.SessionTest.FakeConnection

  setup do
    {:ok, lifecycle} = Lifecycle.start_link([])
    Lifecycle.subscribe(lifecycle)
    # Drain the snapshot delivered on subscribe so later assertions match the
    # broadcasts triggered by the session.
    assert_receive {:chronicle_lifecycle, :disconnected, _}

    # auto_connect: false keeps the session from dialing the (absent) kernel so
    # we can drive its lifecycle handling directly.
    {:ok, session} =
      Session.start_link(connection: :unused, lifecycle: lifecycle, auto_connect: false)

    %{lifecycle: lifecycle, session: session}
  end

  test "marks the lifecycle connected on the first keepalive", %{
    lifecycle: lifecycle,
    session: session
  } do
    send(session, :keepalive_received)

    assert_receive {:chronicle_lifecycle, :connected, _connection_id}, 1_000
    assert Lifecycle.phase(lifecycle) == :connected
  end

  test "only notifies connected on the first keepalive", %{lifecycle: lifecycle, session: session} do
    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    send(session, :keepalive_received)
    # A subsequent keepalive must not re-broadcast :connected (which would make
    # observers re-register needlessly).
    refute_receive {:chronicle_lifecycle, :connected, _}, 100
    assert Lifecycle.phase(lifecycle) == :connected
  end

  test "marks the lifecycle disconnected when the session drops", %{
    lifecycle: lifecycle,
    session: session
  } do
    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    send(session, {:session_down, :closed})

    assert_receive {:chronicle_lifecycle, :disconnected, _}, 1_000
    assert Lifecycle.phase(lifecycle) == :disconnected
  end

  test "drops the session when keepalives stop arriving", %{
    lifecycle: lifecycle,
    session: session
  } do
    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    # The kernel leaves the Connect stream open when its watchdog evicts a
    # client, so the only evidence of a half-disconnect is the keepalive gap.
    backdate_last_keepalive(session, 30_000)
    send(session, :watchdog)

    assert_receive {:chronicle_lifecycle, :disconnected, _}, 1_000
    assert Lifecycle.phase(lifecycle) == :disconnected
  end

  test "keeps the session while keepalives keep arriving", %{
    lifecycle: lifecycle,
    session: session
  } do
    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    send(session, :watchdog)

    refute_receive {:chronicle_lifecycle, :disconnected, _}, 200
    assert Lifecycle.phase(lifecycle) == :connected
  end

  test "does not report a disconnect for a session that never came up", %{session: session} do
    # Repeated failed connect attempts must not spam observers with teardown
    # notifications for a connection they never saw come up.
    send(session, {:session_down, :unavailable})

    refute_receive {:chronicle_lifecycle, :disconnected, _}, 200
  end

  test "schedules only one reconnect when a drop is reported twice", %{session: session} do
    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    # The keepalive loop and the task monitor can both report the same failure.
    send(session, {:session_down, :closed})
    send(session, {:session_down, :closed})

    assert_receive {:chronicle_lifecycle, :disconnected, _}, 1_000
    assert reconnect_timers(session) == 1
  end

  describe "channel rebuild on drop" do
    @tag capture_log: true
    test "requests a fresh channel when an established session drops" do
      {:ok, connection} = FakeConnection.start_link(self())
      {:ok, session} = Session.start_link(connection: connection, auto_connect: false)

      # A live watchdog is what marks the session as actually running on a
      # channel (unit-level stand-in for a started keepalive task).
      :sys.replace_state(session, fn state -> %{state | watchdog_timer: make_ref()} end)

      send(session, {:session_down, :stream_ended})

      # Retrying on the same channel could loop forever: Connection cannot
      # always observe the death that took the session down.
      assert_receive :reconnect_requested, 1_000
    end

    test "does not request a fresh channel for a session that never came up" do
      {:ok, connection} = FakeConnection.start_link(self())
      {:ok, session} = Session.start_link(connection: connection, auto_connect: false)

      send(session, {:session_down, :unavailable})

      refute_receive :reconnect_requested, 200
    end

    @tag capture_log: true
    test "requests a fresh channel when the session fails to start on the channel" do
      {:ok, connection} = FakeConnection.start_link(self())
      {:ok, session} = Session.start_link(connection: connection, auto_connect: false)

      # The fake channel is connected as far as Connection is concerned but
      # cannot carry the Connect RPC — the shape of a stale channel.
      send(session, :connect)

      assert_receive :reconnect_requested, 1_000
    end
  end

  defp backdate_last_keepalive(session, by_ms) do
    :sys.replace_state(session, fn state ->
      %{state | last_keepalive: state.last_keepalive - by_ms}
    end)
  end

  defp reconnect_timers(session) do
    state = :sys.get_state(session)
    if state.reconnect_timer, do: 1, else: 0
  end
end
