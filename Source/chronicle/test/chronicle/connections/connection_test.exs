# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{Connection, ConnectionString}

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
      # A stable stand-in for the adapter's connection process — building the
      # channel around the connect task's own pid would hand the connection a
      # conn_pid that is already dead, which now triggers a reconnect.
      conn_pid = spawn(fn -> Process.sleep(:infinity) end)

      connect_fun = fn _target, _opts ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        send(test, {:attempt, attempt})

        if attempt < 2 do
          {:error, :unavailable}
        else
          {:ok, channel_with_conn(conn_pid)}
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

  describe "forced reconnect" do
    test "reconnect/1 drops the channel and dials a fresh one" do
      test = self()
      conn_pid = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      connect_fun = fn _target, _opts ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        send(test, {:attempt, attempt})
        {:ok, channel_with_conn(conn_pid)}
      end

      conn =
        start(
          connect_fun: connect_fun,
          disconnect_fun: fn channel -> send(test, {:disconnected, channel}) end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:attempt, 0}, 1_000

      # A caller (the session watchdog) has evidence the channel is dead even
      # though this process observed nothing — it must be able to force a
      # rebuild.
      Connection.reconnect(conn)

      assert_receive {:disconnected, _old_channel}, 1_000
      assert_receive {:attempt, 1}, 1_000
      assert Connection.connect(conn, 1_000) == :ok
    end

    test "reconnect/1 without a connected channel leaves the dial loop alone" do
      test = self()

      conn =
        start(
          connect_fun: fn _target, _opts ->
            send(test, :dialed)
            {:error, :unavailable}
          end
        )

      # auto_connect: false — no channel and no dial in flight; a forced
      # reconnect must not start one of its own.
      Connection.reconnect(conn)

      refute_receive :dialed, 200
      refute Connection.connected?(conn)
    end
  end

  describe "connection process exit" do
    test "reconnects when the connection process dies" do
      test = self()
      first_conn = spawn(fn -> Process.sleep(:infinity) end)
      replacement_conn = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      connect_fun = fn _target, _opts ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        send(test, {:attempt, attempt})
        {:ok, channel_with_conn(if(attempt == 0, do: first_conn, else: replacement_conn))}
      end

      conn =
        start(connect_fun: connect_fun, disconnect_fun: fn _ch -> :ok end, auto_connect: true)

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:attempt, 0}, 1_000

      # The adapter's connection process crashing sends no transport-down
      # message anywhere useful — only the monitor sees it.
      Process.exit(first_conn, :kill)

      assert_receive {:attempt, 1}, 1_000
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

  describe "gRPC target format" do
    test "uses the ipv4: scheme prefix for a plain host" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:target, "ipv4:localhost:35000"}
    end

    test "uses the ipv6: scheme prefix and brackets for an IPv6 host" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://[::1]:9000?disableTls=true",
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:target, "ipv6:[::1]:9000"}
    end
  end

  describe "DNS SRV resolution" do
    test "resolves via :resolve_fun and connects to the selected address" do
      test_pid = self()
      channel = channel_with_conn(self())

      resolve_fun = fn host, name_server ->
        send(test_pid, {:resolve_called, host, name_server})
        {:ok, [%ConnectionString.ServerAddress{host: "srv-resolved-host", port: 9_999}]}
      end

      conn =
        start(
          connection_string: "chronicle+srv://my-service?disableTls=true&srvNameServer=1.1.1.1",
          resolve_fun: resolve_fun,
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:resolve_called, "my-service", "1.1.1.1"}
      assert_receive {:target, "ipv4:srv-resolved-host:9999"}
    end

    test "retries the reconnect loop when SRV resolution fails" do
      test_pid = self()
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      channel = channel_with_conn(self())

      resolve_fun = fn _host, _name_server ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
        send(test_pid, {:resolve_attempt, attempt})

        if attempt < 1 do
          {:error, :srv_no_records}
        else
          {:ok, [%ConnectionString.ServerAddress{host: "finally-up", port: 1_234}]}
        end
      end

      conn =
        start(
          connection_string: "chronicle+srv://my-service?disableTls=true",
          resolve_fun: resolve_fun,
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 2_000) == :ok
      assert_receive {:resolve_attempt, 0}
      assert_receive {:resolve_attempt, 1}
      assert_receive {:target, "ipv4:finally-up:1234"}
    end
  end

  describe "multi-host load balancing" do
    test "round_robin cycles through configured hosts on reconnect" do
      test_pid = self()
      conn_pid = spawn(fn -> Process.sleep(:infinity) end)
      channel = channel_with_conn(conn_pid)

      connect_fun = fn target, _opts ->
        send(test_pid, {:target, target})
        {:ok, channel}
      end

      conn =
        start(
          connection_string:
            "chronicle://host1:1000,host2:2000?disableTls=true&loadBalancer=round-robin",
          connect_fun: connect_fun,
          disconnect_fun: fn _ch -> :ok end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:target, first_target}

      send(conn, {:gun_down, conn_pid, :http, :closed})
      assert_receive {:target, second_target}
      assert Connection.connect(conn, 1_000) == :ok

      assert first_target in ["ipv4:host1:1000", "ipv4:host2:2000"]
      assert second_target in ["ipv4:host1:1000", "ipv4:host2:2000"]
      # Two hosts round-robining on consecutive attempts always alternates,
      # regardless of the random starting offset.
      assert first_target != second_target
    end

    test "least_connections (the default) picks the candidate reporting the fewest connections" do
      test_pid = self()
      channel = channel_with_conn(self())

      probe_fun = fn
        :count, %{host: "busy"}, _cs -> {:ok, 99}
        :count, %{host: "idle"}, _cs -> {:ok, 0}
        :reserve, _address, _cs -> {:ok, :reserved}
      end

      conn =
        start(
          connection_string: "chronicle://busy:1000,idle:2000?disableTls=true",
          probe_fun: probe_fun,
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:target, "ipv4:idle:2000"}
    end

    test "the :load_balancer option overrides the connection string's strategy" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          # Defaults to :least_connections, which would call probe_fun below —
          # overriding to :random must skip probing entirely.
          connection_string: "chronicle://host1:1000,host2:2000?disableTls=true",
          load_balancer: :random,
          probe_fun: fn _action, _address, _cs ->
            flunk("least-connections probing should not run once overridden to :random")
          end,
          connect_fun: fn target, _opts ->
            send(test_pid, {:target, target})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:target, target}
      assert target in ["ipv4:host1:1000", "ipv4:host2:2000"]
    end
  end

  describe "TLS validation" do
    test "skips certificate chain validation by default" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://localhost:35000",
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}
      assert opts[:cred].ssl[:verify] == :verify_none
    end

    test "validates the certificate chain when the connection string sets skipTlsValidation=false" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://localhost:35000?skipTlsValidation=false",
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}
      assert opts[:cred].ssl[:verify] == :verify_peer
      assert opts[:cred].ssl[:cacerts] != nil
    end

    test "validates the certificate chain when the :skip_tls_validation option is set to false" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://localhost:35000",
          skip_tls_validation: false,
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}
      assert opts[:cred].ssl[:verify] == :verify_peer
      assert opts[:cred].ssl[:cacerts] != nil
    end

    test "omits credentials entirely when disableTls=true" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}
      refute Keyword.has_key?(opts, :cred)
    end
  end
end
