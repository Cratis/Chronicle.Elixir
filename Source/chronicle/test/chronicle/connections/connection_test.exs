# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Connection

  # A connection process exposed through adapter_payload so the connection can
  # extract it for liveness monitoring (mirrors the gun adapter shape).
  defp channel_with_conn(pid), do: %{adapter_payload: %{conn_pid: pid}}

  defp start(opts) do
    base = [
      connection_string: "chronicle://localhost:35000?disableTls=true",
      reconnect_base_delay: 10,
      reconnect_max_delay: 50,
      auto_connect: false
    ]

    {:ok, pid} = Connection.start_link(Keyword.merge(base, opts))
    pid
  end

  describe "before connecting" do
    test "reports not connected" do
      conn = start([])
      refute Connection.connected?(conn)
    end

    test "channel/1 returns {:error, :not_connected}" do
      conn = start([])
      assert Connection.channel(conn) == {:error, :not_connected}
    end
  end

  describe "successful connect" do
    test "becomes connected and exposes the channel" do
      channel = channel_with_conn(self())
      conn = start(connect_fun: fn _target, _opts -> {:ok, channel} end, auto_connect: true)

      assert Connection.connect(conn, 1_000) == :ok
      assert Connection.connected?(conn)
      assert Connection.channel(conn) == {:ok, channel}
    end

    test "await returns immediately when already connected" do
      channel = channel_with_conn(self())
      conn = start(connect_fun: fn _target, _opts -> {:ok, channel} end, auto_connect: true)

      assert Connection.connect(conn, 1_000) == :ok
      assert Connection.connect(conn, 1_000) == :ok
    end
  end

  describe "connect failure and retry" do
    test "retries until it succeeds" do
      test = self()
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      connect_fun = fn _target, _opts ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        send(test, {:attempt, attempt})

        if attempt < 2 do
          {:error, :unavailable}
        else
          {:ok, channel_with_conn(self())}
        end
      end

      conn = start(connect_fun: connect_fun, auto_connect: true)

      assert Connection.connect(conn, 2_000) == :ok
      assert_receive {:attempt, 0}, 1_000
      assert_receive {:attempt, 1}, 1_000
      assert_receive {:attempt, 2}, 1_000
    end
  end

  describe "await timeout" do
    test "returns {:error, :timeout} when connecting takes too long" do
      channel = channel_with_conn(self())

      connect_fun = fn _target, _opts ->
        Process.sleep(300)
        {:ok, channel}
      end

      conn = start(connect_fun: connect_fun, auto_connect: true)
      assert Connection.connect(conn, 50) == {:error, :timeout}
    end
  end

  describe "connection down" do
    test "drops the channel and reconnects" do
      test = self()
      conn_pid = spawn(fn -> Process.sleep(:infinity) end)
      channel = channel_with_conn(conn_pid)

      connect_fun = fn _target, _opts ->
        send(test, :connected)
        {:ok, channel}
      end

      conn =
        start(connect_fun: connect_fun, disconnect_fun: fn _ch -> :ok end, auto_connect: true)

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive :connected, 1_000

      send(conn, {:gun_down, conn_pid, :http, :closed})

      # It reconnects on its own.
      assert_receive :connected, 1_000
      assert Connection.connect(conn, 1_000) == :ok
    end
  end

  describe "disconnect" do
    test "stops the process" do
      channel = channel_with_conn(self())
      conn = start(connect_fun: fn _t, _o -> {:ok, channel} end, auto_connect: true)
      assert Connection.connect(conn, 1_000) == :ok

      ref = Process.monitor(conn)
      assert Connection.disconnect(conn) == :ok
      assert_receive {:DOWN, ^ref, :process, ^conn, :normal}, 1_000
    end
  end
end
