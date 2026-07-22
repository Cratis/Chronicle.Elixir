# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.SessionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{Lifecycle, Session}

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
