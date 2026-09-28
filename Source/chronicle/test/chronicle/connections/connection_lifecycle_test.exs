# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionLifecycleTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.Connection

  test "supervised connection shutdown disconnects its channel and token provider" do
    parent = self()

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Connection,
           connection_string: "chronicle://user:pass@localhost?disableTls=true",
           connect_fun: fn _, opts ->
             [{_, provider: provider} | _] = opts[:interceptors]
             send(parent, {:provider, provider})
             {:ok, %{}}
           end,
           disconnect_fun: fn channel -> send(parent, {:disconnected, channel}) end}
        ],
        strategy: :one_for_one
      )

    [{_, connection, _, _}] = Supervisor.which_children(supervisor)
    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:provider, provider}
    monitor = Process.monitor(provider)

    assert :ok = Supervisor.stop(supervisor)
    assert_receive {:disconnected, %{}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
  end

  test "an unexpected token provider exit restarts its owning connection" do
    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Connection,
           connection_string: "chronicle://user:pass@localhost?disableTls=true",
           auto_connect: false}
        ],
        strategy: :one_for_one
      )

    [{_, connection, _, _}] = Supervisor.which_children(supervisor)
    provider = :sys.get_state(connection).token_provider
    monitor = Process.monitor(connection)

    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :killed}, 2_000

    replacement =
      await_replacement(supervisor, connection, System.monotonic_time(:millisecond) + 2_000)

    assert is_pid(replacement)
    assert Process.alive?(:sys.get_state(replacement).token_provider)
    assert :ok = Supervisor.stop(supervisor)
  end

  test "an in-flight dial is disconnected even if the owner stops before the result arrives" do
    parent = self()

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Connection,
           connection_string: "chronicle://localhost?disableTls=true",
           connect_fun: fn _, _ ->
             send(parent, {:dialing, self()})

             receive do
               :finish -> {:ok, %{}}
             end
           end,
           disconnect_fun: fn channel -> send(parent, {:late_disconnect, channel}) end}
        ],
        strategy: :one_for_one
      )

    assert_receive {:dialing, task}, 2_000
    assert :ok = Supervisor.stop(supervisor)
    send(task, :finish)
    assert_receive {:late_disconnect, %{}}, 2_000
  end

  test "shutdown during a stalled compatibility RPC closes the Mint socket" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    before_count = DynamicSupervisor.count_children(GRPC.Client.Supervisor).active
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, client} =
      Chronicle.Client.start_link(
        name: :blocked_compatibility_client,
        discover: false,
        connection_string: "chronicle://localhost:#{port}?disableTls=true"
      )

    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    connection = Chronicle.Client.connection_name(:blocked_compatibility_client)
    assert :ok = Connection.connect(connection, 5_000)
    transport = :sys.get_state(connection).transport
    transport_supervisor = :sys.get_state(transport).supervisor
    transport_monitor = Process.monitor(transport)
    supervisor_monitor = Process.monitor(transport_supervisor)
    assert DynamicSupervisor.count_children(transport_supervisor).active == 1

    caller = spawn(fn -> Connection.append_channel(connection) end)
    assert_check_in_flight(connection, System.monotonic_time(:millisecond) + 2_000)
    started = System.monotonic_time(:millisecond)
    assert :ok = Supervisor.stop(client)
    assert System.monotonic_time(:millisecond) - started < 4_000
    assert_closed(socket)
    :gen_tcp.close(socket)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
    assert_receive {:DOWN, ^supervisor_monitor, :process, ^transport_supervisor, _}, 2_000
    assert_child_count(before_count, System.monotonic_time(:millisecond) + 2_000)
    refute Process.alive?(caller)
  end

  test "a killed connection closes its supervised transport without terminate" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    before_count = DynamicSupervisor.count_children(GRPC.Client.Supervisor).active
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, connection} =
      Connection.start_link(connection_string: "chronicle://localhost:#{port}?disableTls=true")

    Process.unlink(connection)
    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    assert :ok = Connection.connect(connection, 5_000)
    transport = :sys.get_state(connection).transport
    transport_supervisor = :sys.get_state(transport).supervisor
    owner_monitor = Process.monitor(connection)
    transport_monitor = Process.monitor(transport)
    supervisor_monitor = Process.monitor(transport_supervisor)

    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^connection, :killed}, 2_000
    assert_closed(socket)
    :gen_tcp.close(socket)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
    assert_receive {:DOWN, ^supervisor_monitor, :process, ^transport_supervisor, _}, 2_000
    assert_child_count(before_count, System.monotonic_time(:millisecond) + 2_000)
  end

  test "a dead transport owner stops its connection" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, connection} =
      Connection.start_link(connection_string: "chronicle://localhost:#{port}?disableTls=true")

    Process.unlink(connection)
    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert :ok = Connection.connect(connection, 5_000)
    transport = :sys.get_state(connection).transport
    owner_monitor = Process.monitor(connection)

    Process.exit(transport, :kill)

    assert_receive {:DOWN, ^owner_monitor, :process, ^connection, {:transport_down, :killed}},
                   2_000
  end

  test "an abnormally exiting gRPC orchestrator does not leave node-wide channel state" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, connection} =
      Connection.start_link(connection_string: "chronicle://localhost:#{port}?disableTls=true")

    Process.unlink(connection)

    on_exit(fn ->
      try do
        GenServer.stop(connection)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert :ok = Connection.connect(connection, 5_000)
    {:ok, channel} = Connection.channel(connection)
    ref = channel.ref
    # Pins grpc 1.0.5's private keys; if grpc renames them this fails instead of leaking silently.
    assert :persistent_term.get({GRPC.Client.Connection, :channel, ref}, nil) != nil

    [{orchestrator, _}] =
      Registry.lookup(GRPC.Client.Registry, {GRPC.Client.Connection, ref})

    Process.exit(orchestrator, :kill)
    assert_erased(ref, System.monotonic_time(:millisecond) + 2_000)
  end

  test "a crashing gRPC orchestrator cannot restart an orphan during teardown" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    before_count = DynamicSupervisor.count_children(GRPC.Client.Supervisor).active
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, client} =
      Chronicle.Client.start_link(
        name: :crashing_grpc_client,
        discover: false,
        connection_string: "chronicle://localhost:#{port}?disableTls=true"
      )

    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    connection = Chronicle.Client.connection_name(:crashing_grpc_client)
    assert :ok = Connection.connect(connection, 5_000)
    transport = :sys.get_state(connection).transport
    transport_supervisor = :sys.get_state(transport).supervisor
    transport_monitor = Process.monitor(transport)
    supervisor_monitor = Process.monitor(transport_supervisor)
    {:ok, channel} = Connection.channel(connection)

    [{orchestrator, _}] =
      Registry.lookup(GRPC.Client.Registry, {GRPC.Client.Connection, channel.ref})

    Process.exit(orchestrator, :kill)
    assert :ok = Supervisor.stop(client)
    assert_closed(socket)
    :gen_tcp.close(socket)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
    assert_receive {:DOWN, ^supervisor_monitor, :process, ^transport_supervisor, _}, 2_000
    assert_child_count(before_count, System.monotonic_time(:millisecond) + 2_000)
  end

  test "an OAuth fetch in flight does not delay supervisor shutdown" do
    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Connection,
           connection_string: "chronicle://user:pass@localhost?disableTls=true",
           auto_connect: false}
        ],
        strategy: :one_for_one
      )

    [{_, connection, _, _}] = Supervisor.which_children(supervisor)
    provider = :sys.get_state(connection).token_provider
    parent = self()

    :sys.replace_state(provider, fn state ->
      %{
        state
        | fetch_fun: fn _ ->
            send(parent, :fetching_token)

            receive do
              :release -> {:ok, {"token", 3600}}
            end
          end
      }
    end)

    spawn(fn ->
      try do
        Chronicle.Connections.TokenProvider.authorization_headers(provider)
      catch
        :exit, _ -> :ok
      end
    end)

    assert_receive :fetching_token
    started = System.monotonic_time(:millisecond)
    assert :ok = Supervisor.stop(supervisor)
    assert System.monotonic_time(:millisecond) - started < 2_000
    refute Process.alive?(provider)
  end

  test "restarting Chronicle.Client closes each real Mint connection and socket" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    before_count = DynamicSupervisor.count_children(GRPC.Client.Supervisor).active

    on_exit(fn -> :gen_tcp.close(listener) end)

    for _ <- 1..3 do
      {:ok, client} =
        Chronicle.Client.start_link(
          name: :lifecycle_test_client,
          discover: false,
          connection_string: "chronicle://localhost:#{port}?disableTls=true"
        )

      {:ok, socket} = :gen_tcp.accept(listener, 5_000)

      connection = Chronicle.Client.connection_name(:lifecycle_test_client)
      assert :ok = Connection.connect(connection, 5_000)
      transport = :sys.get_state(connection).transport
      transport_supervisor = :sys.get_state(transport).supervisor
      transport_monitor = Process.monitor(transport)
      supervisor_monitor = Process.monitor(transport_supervisor)
      assert DynamicSupervisor.count_children(transport_supervisor).active == 1
      assert DynamicSupervisor.count_children(GRPC.Client.Supervisor).active == before_count

      assert :ok = Supervisor.stop(client)
      assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
      assert_receive {:DOWN, ^supervisor_monitor, :process, ^transport_supervisor, _}, 2_000
      assert_closed(socket)
      :gen_tcp.close(socket)
      assert_child_count(before_count, System.monotonic_time(:millisecond) + 2_000)
    end
  end

  defp assert_check_in_flight(connection, deadline) do
    if :sys.get_state(connection).append_check == nil do
      assert System.monotonic_time(:millisecond) < deadline,
             "compatibility RPC did not start"

      Process.sleep(10)
      assert_check_in_flight(connection, deadline)
    end
  end

  defp await_replacement(supervisor, previous, deadline) do
    case Supervisor.which_children(supervisor) do
      [{_, pid, _, _}] when is_pid(pid) and pid != previous ->
        pid

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "supervisor did not restart the connection"

        Process.sleep(10)
        await_replacement(supervisor, previous, deadline)
    end
  end

  defp assert_erased(ref, deadline) do
    cond do
      :persistent_term.get({GRPC.Client.Connection, :channel, ref}, nil) == nil and
          :persistent_term.get({GRPC.Client.Connection, :lb, ref}, nil) == nil ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("grpc channel state for #{inspect(ref)} was not erased")

      true ->
        Process.sleep(20)
        assert_erased(ref, deadline)
    end
  end

  defp assert_child_count(expected, deadline) do
    count = DynamicSupervisor.count_children(GRPC.Client.Supervisor).active

    if count != expected do
      assert System.monotonic_time(:millisecond) < deadline,
             "gRPC supervisor still has #{count} children, expected #{expected}"

      Process.sleep(10)
      assert_child_count(expected, deadline)
    end
  end

  defp assert_closed(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, _buffered_data} -> assert_closed(socket)
      {:error, :closed} -> :ok
      other -> flunk("socket stayed open: #{inspect(other)}")
    end
  end
end
