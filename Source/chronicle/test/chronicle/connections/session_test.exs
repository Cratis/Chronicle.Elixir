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
  def handle_call(:session_channel, _from, test_pid), do: {:reply, {:ok, %{fake: true}}, test_pid}

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
  alias Chronicle.Observers.ReconnectBackoff

  setup do
    {:ok, lifecycle} = Lifecycle.start_link([])
    Lifecycle.subscribe(lifecycle)
    # Drain the snapshot delivered on subscribe so later assertions match the
    # broadcasts triggered by the session.
    assert_receive {:chronicle_lifecycle, :disconnected, _}

    # auto_connect: false keeps the session from dialing the (absent) kernel so
    # we can drive its lifecycle handling directly.
    {:ok, session} =
      start_session(connection: :unused, lifecycle: lifecycle, auto_connect: false)

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

  test "keeps the session within a configured keepalive timeout", %{lifecycle: lifecycle} do
    {:ok, session} =
      start_session(
        connection: :unused,
        lifecycle: lifecycle,
        auto_connect: false,
        keepalive_timeout: 60_000
      )

    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    # Longer than the 5 second default, shorter than the configured timeout.
    backdate_last_keepalive(session, 30_000)
    send(session, :watchdog)

    refute_receive {:chronicle_lifecycle, :disconnected, _}, 200
  end

  test "drops the session after a configured keepalive timeout", %{lifecycle: lifecycle} do
    {:ok, session} =
      start_session(
        connection: :unused,
        lifecycle: lifecycle,
        auto_connect: false,
        keepalive_timeout: 1_000
      )

    send(session, :keepalive_received)
    assert_receive {:chronicle_lifecycle, :connected, _}, 1_000

    backdate_last_keepalive(session, 2_000)
    send(session, :watchdog)

    assert_receive {:chronicle_lifecycle, :disconnected, _}, 1_000
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
      {:ok, session} = start_session(connection: connection, auto_connect: false)

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
      {:ok, session} = start_session(connection: connection, auto_connect: false)

      send(session, {:session_down, :unavailable})

      refute_receive :reconnect_requested, 200
    end

    @tag capture_log: true
    test "requests a fresh channel when the session fails to start on the channel" do
      {:ok, connection} = FakeConnection.start_link(self())
      {:ok, session} = start_session(connection: connection, auto_connect: false)

      # The fake channel is connected as far as Connection is concerned but
      # cannot carry the Connect RPC — the shape of a stale channel.
      send(session, :connect)

      # Starting the failed RPC may load gRPC modules while other specs run.
      assert_receive :reconnect_requested, 5_000
    end
  end

  describe "an observer reports the session lost" do
    @describetag capture_log: true

    setup %{lifecycle: lifecycle} do
      {:ok, connection} = FakeConnection.start_link(self())

      {:ok, session} =
        start_session(connection: connection, lifecycle: lifecycle, auto_connect: false)

      send(session, :keepalive_received)
      assert_receive {:chronicle_lifecycle, :connected, connection_id}, 1_000
      # A live watchdog marks the session as running on a channel.
      :sys.replace_state(session, fn state -> %{state | watchdog_timer: make_ref()} end)

      %{session: session, connection_id: connection_id}
    end

    test "drops the session and reconnects with a new connection id", %{
      lifecycle: lifecycle,
      session: session,
      connection_id: connection_id
    } do
      Session.session_lost(session, connection_id)

      assert_receive {:chronicle_lifecycle, :disconnected, ^connection_id}, 1_000
      # The next connect reads the lifecycle's id, which the drop rotated.
      assert Lifecycle.connection_id(lifecycle) != connection_id
      assert_receive :reconnect_requested, 1_000
      assert reconnect_timers(session) == 1
    end

    test "ignores a report for a connection id it no longer uses", %{
      lifecycle: lifecycle,
      session: session
    } do
      Session.session_lost(session, "a-connection-id-from-before")

      settle(session, lifecycle)
      refute_received {:chronicle_lifecycle, :disconnected, _}
      refute_received :reconnect_requested
      assert Lifecycle.phase(lifecycle) == :connected
    end

    test "drops the session only once when several observers report it", %{
      lifecycle: lifecycle,
      session: session,
      connection_id: connection_id
    } do
      Session.session_lost(session, connection_id)
      Session.session_lost(session, connection_id)

      assert_receive {:chronicle_lifecycle, :disconnected, _}, 1_000
      settle(session, lifecycle)
      refute_received {:chronicle_lifecycle, :disconnected, _}
      assert_received :reconnect_requested
      refute_received :reconnect_requested
    end

    test "reports the disconnect for a session lost before its first keepalive", %{
      lifecycle: lifecycle
    } do
      {:ok, connection} = FakeConnection.start_link(self())

      {:ok, session} =
        start_session(connection: connection, lifecycle: lifecycle, auto_connect: false)

      :sys.replace_state(session, fn state -> %{state | watchdog_timer: make_ref()} end)
      lifecycle_id = Lifecycle.connection_id(lifecycle)

      Session.session_lost(session, :sys.get_state(session).connection_id)

      # The disconnect rotates the connection id the next session connects with.
      assert_receive {:chronicle_lifecycle, :disconnected, ^lifecycle_id}, 1_000
      assert Lifecycle.connection_id(lifecycle) != lifecycle_id
    end
  end

  describe "reconnecting" do
    @describetag capture_log: true

    # Waits of base 1s and longest 30s; the jitter of 0 lands every wait at the
    # start of its upper half, so the scheduled waits are half the ceiling.
    setup %{lifecycle: lifecycle} do
      {:ok, connection} = FakeConnection.start_link(self())
      {:ok, clock} = Agent.start_link(fn -> 0 end)

      {:ok, session} =
        start_session(
          connection: connection,
          lifecycle: lifecycle,
          auto_connect: false,
          jitter_fun: fn -> 0.0 end,
          now_fun: fn -> Agent.get(clock, & &1) end
        )

      %{session: session, clock: clock}
    end

    test "waits longer while connecting keeps failing, up to thirty seconds", %{
      session: session
    } do
      delays =
        for _ <- 1..7 do
          # The fake channel cannot carry the Connect call, so every attempt fails.
          send(session, :connect)
          assert_receive {:scheduled, :connect, delay}, 5_000
          delay
        end

      assert delays == [500, 1_000, 2_000, 4_000, 8_000, 15_000, 15_000]
    end

    test "lands each wait at random in the upper half of its ceiling", %{lifecycle: lifecycle} do
      {:ok, connection} = FakeConnection.start_link(self())

      {:ok, session} =
        start_session(
          connection: connection,
          lifecycle: lifecycle,
          auto_connect: false,
          jitter_fun: fn -> 0.5 end
        )

      send(session, :connect)
      assert_receive {:scheduled, :connect, 750}, 5_000
    end

    test "keeps growing while sessions drop straight after coming up", %{session: session} do
      assert session_drops(session) == 500
      assert session_drops(session) == 1_000
      assert session_drops(session) == 2_000
    end

    test "starts over once a session stayed up for the longest wait", %{
      session: session,
      clock: clock
    } do
      assert session_drops(session) == 500
      assert session_drops(session) == 1_000

      assert session_drops(session, fn -> Agent.update(clock, &(&1 + 30_000)) end) == 500
    end
  end

  # Brings the session up, runs `while_up` and drops the session, returning the
  # wait scheduled before connecting again.
  defp session_drops(session, while_up \\ fn -> :ok end) do
    # Stands in for a connect that succeeded: the attempt was recorded and the
    # session is up on a channel.
    :sys.replace_state(session, fn state ->
      %{
        state
        | reconnect_timer: nil,
          reconnect_backoff: ReconnectBackoff.stream_opened(state.reconnect_backoff),
          watchdog_timer: make_ref()
      }
    end)

    while_up.()
    send(session, {:session_down, :closed})
    assert_receive {:scheduled, :connect, delay}, 1_000
    delay
  end

  # Every scheduled reconnect is reported to the test instead of firing, so a
  # session never dials the absent kernel on its own while a spec runs.
  defp start_session(opts) do
    test = self()

    Session.start_link(
      Keyword.put_new(opts, :send_after_fun, fn message, delay ->
        send(test, {:scheduled, message, delay})
        make_ref()
      end)
    )
  end

  # Waits until the session and the lifecycle have handled everything sent so far.
  defp settle(session, lifecycle) do
    :sys.get_state(session)
    :sys.get_state(lifecycle)
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
