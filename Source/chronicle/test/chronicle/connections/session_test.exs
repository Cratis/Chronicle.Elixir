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
end
