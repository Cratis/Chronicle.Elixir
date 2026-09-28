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

      assert :ok =
               Connection.connect(Chronicle.Client.connection_name(:lifecycle_test_client), 5_000)

      assert DynamicSupervisor.count_children(GRPC.Client.Supervisor).active == before_count + 1

      assert :ok = Supervisor.stop(client)
      assert_closed(socket)
      :gen_tcp.close(socket)
      assert_child_count(before_count, System.monotonic_time(:millisecond) + 2_000)
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
