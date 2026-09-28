# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{ClientCertificate, Connection, ConnectionString}
  alias GRPC.Client.Adapters.Mint.StreamResponseProcess

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

  describe "authentication" do
    test "installs the per-call auth interceptor for client credentials" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://user:pass@localhost:35000?disableTls=true",
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}

      # The token travels per RPC via the interceptor — never as a channel
      # header, where its expiry would silently invalidate the channel.
      assert [
               {Chronicle.Connections.AuthInterceptor, provider: provider},
               Chronicle.Connections.TransportFailureInterceptor
             ] = opts[:interceptors]

      assert is_pid(provider) and Process.alive?(provider)
      assert opts[:headers] == []
    end

    test "keeps the static api-key as a channel header without an auth interceptor" do
      test_pid = self()
      channel = channel_with_conn(self())

      conn =
        start(
          connection_string: "chronicle://localhost:35000?apiKey=abc&disableTls=true",
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel}
          end,
          auto_connect: true
        )

      assert Connection.connect(conn, 1_000) == :ok
      assert_receive {:opts, opts}
      assert opts[:headers] == [{"api-key", "abc"}]
      assert opts[:interceptors] == [Chronicle.Connections.TransportFailureInterceptor]
    end

    test "adds no auth at all without credentials" do
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
      assert opts[:headers] == []
      assert opts[:interceptors] == [Chronicle.Connections.TransportFailureInterceptor]
      assert opts[:adapter] == GRPC.Client.Adapters.Mint
    end
  end

  describe "client certificates" do
    @tag :tmp_dir
    test "loads a password-protected PKCS#12 client certificate into the gRPC TLS options", %{
      tmp_dir: tmp_dir
    } do
      path = certificate_fixture(tmp_dir)
      test_pid = self()

      conn =
        start(
          connection_string:
            "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret",
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel_with_conn(test_pid)}
          end,
          auto_connect: true
        )

      assert :ok = Connection.connect(conn, 1_000)
      assert_receive {:opts, opts}
      assert is_binary(opts[:cred].ssl[:cert])

      assert match?(
               %{algorithm: :rsa, sign_fun: fun} when is_function(fun, 3),
               opts[:cred].ssl[:key]
             )

      assert opts[:cred].ssl[:verify] == :verify_none
    end

    @tag :tmp_dir
    test "loads a PEM bundle containing the certificate and private key", %{tmp_dir: tmp_dir} do
      certificate_fixture(tmp_dir)
      bundle = Path.join(tmp_dir, "bundle.pem")

      File.write!(
        bundle,
        File.read!(Path.join(tmp_dir, "cert.pem")) <> File.read!(Path.join(tmp_dir, "key.pem"))
      )

      certificate =
        bundle
        |> then(&"chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(&1)}")
        |> ConnectionString.parse()
        |> ClientCertificate.load!()

      assert is_binary(certificate[:cert])
      assert match?(%{algorithm: :rsa, sign_fun: fun} when is_function(fun, 3), certificate[:key])
    end

    @tag :tmp_dir
    test "decrypts an encrypted PEM private key and rejects an incorrect password", %{
      tmp_dir: tmp_dir
    } do
      certificate_fixture(tmp_dir)
      encrypted_key = Path.join(tmp_dir, "encrypted-key.pem")
      bundle = Path.join(tmp_dir, "encrypted-bundle.pem")

      {_, 0} =
        System.cmd(
          "openssl",
          [
            "pkcs8",
            "-topk8",
            "-in",
            Path.join(tmp_dir, "key.pem"),
            "-out",
            encrypted_key,
            "-passout",
            "pass:secret"
          ],
          stderr_to_stdout: true
        )

      File.write!(bundle, File.read!(Path.join(tmp_dir, "cert.pem")) <> File.read!(encrypted_key))

      connection_string =
        "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(bundle)}"

      assert [cert: cert, key: %{algorithm: :rsa, sign_fun: fun}] =
               connection_string
               |> Kernel.<>("&certificatePassword=secret")
               |> ConnectionString.parse()
               |> ClientCertificate.load!()

      assert is_binary(cert) and is_function(fun, 3)

      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(connection_string <> "&certificatePassword=incorrect")

      assert message =~ "invalid client certificate or password"
    end

    @tag :tmp_dir
    test "preserves custom gRPC trust settings while installing the client certificate", %{
      tmp_dir: tmp_dir
    } do
      path = certificate_fixture(tmp_dir)
      test_pid = self()
      custom = GRPC.Credential.new(ssl: [verify: :verify_peer, cacerts: []])

      conn =
        start(
          connection_string:
            "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret&skipTlsValidation=false",
          grpc_options: [cred: custom],
          connect_fun: fn _target, opts ->
            send(test_pid, {:opts, opts})
            {:ok, channel_with_conn(test_pid)}
          end,
          auto_connect: true
        )

      assert :ok = Connection.connect(conn, 1_000)
      assert_receive {:opts, opts}
      assert opts[:cred].ssl[:verify] == :verify_peer
      assert opts[:cred].ssl[:cacerts] == []
      refute Keyword.has_key?(opts[:cred].ssl, :verify_fun)
      refute Keyword.has_key?(opts[:cred].ssl, :partial_chain)
      assert is_binary(opts[:cred].ssl[:cert])

      assert match?(
               %{algorithm: :rsa, sign_fun: fun} when is_function(fun, 3),
               opts[:cred].ssl[:key]
             )
    end

    @tag :tmp_dir
    test "preserves a credential's CRL policy with a client identity", %{
      tmp_dir: tmp_dir
    } do
      path = certificate_fixture(tmp_dir)
      parent = self()
      credential = GRPC.Credential.new(ssl: [verify: :verify_peer, cacerts: [], crl_check: :peer])

      conn =
        start(
          connection_string:
            "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret&skipTlsValidation=false",
          grpc_options: [cred: credential],
          connect_fun: fn _target, opts ->
            send(parent, {:ssl, opts[:cred].ssl})
            {:ok, channel_with_conn(parent)}
          end,
          auto_connect: true
        )

      assert :ok = Connection.connect(conn, 5_000)
      assert_receive {:ssl, ssl}
      assert ssl[:crl_check] == :peer
      refute Keyword.has_key?(ssl, :verify_fun)
      refute Keyword.has_key?(ssl, :partial_chain)
      assert is_binary(ssl[:cert])
    end

    @tag :tmp_dir
    test "preserves a custom verify_none credential with a client identity", %{tmp_dir: tmp_dir} do
      path = certificate_fixture(tmp_dir)
      parent = self()
      custom = GRPC.Credential.new(ssl: [verify: :verify_none])

      conn =
        start(
          connection_string:
            "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret&skipTlsValidation=false",
          grpc_options: [cred: custom],
          connect_fun: fn _target, opts ->
            send(parent, {:ssl, opts[:cred].ssl})
            {:ok, channel_with_conn(parent)}
          end,
          auto_connect: true
        )

      assert :ok = Connection.connect(conn, 1_000)
      assert_receive {:ssl, ssl}
      assert ssl[:verify] == :verify_none
      refute Keyword.has_key?(ssl, :verify_fun)
      refute Keyword.has_key?(ssl, :partial_chain)
      assert is_binary(ssl[:cert])
    end

    @tag :tmp_dir
    test "uses the same client certificate for OAuth TLS", %{tmp_dir: tmp_dir} do
      path = certificate_fixture(tmp_dir)

      connection_string =
        ConnectionString.parse(
          "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"
        )

      certificate = ClientCertificate.load!(connection_string)
      opts = Chronicle.Connections.Auth.transport_opts(false, false, certificate)
      assert opts[:transport_opts][:cert] == certificate[:cert]
      assert opts[:transport_opts][:key] == certificate[:key]
      assert opts[:transport_opts][:verify] == :verify_peer
      refute Keyword.has_key?(opts[:transport_opts], :verify_fun)
      refute Keyword.has_key?(opts[:transport_opts], :partial_chain)
    end

    @tag :tmp_dir
    test "rejects a wrong PKCS#12 password without dialing", %{tmp_dir: tmp_dir} do
      path = certificate_fixture(tmp_dir)

      connection_string =
        "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=wrong"

      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(connection_string)

      assert message =~ "client certificate"
      assert message =~ path
    end

    @tag :tmp_dir
    test "rejects a PEM certificate without its private key", %{tmp_dir: tmp_dir} do
      certificate_fixture(tmp_dir)
      path = Path.join(tmp_dir, "cert.pem")

      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(
                 "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}"
               )

      assert message =~ "invalid client certificate"
    end

    @tag :tmp_dir
    test "malformed PEM and PKCS#12 never expose key bytes in startup failures", %{tmp_dir: dir} do
      certificate_fixture(dir)
      cert = File.read!(Path.join(dir, "cert.pem"))
      key = File.read!(Path.join(dir, "key.pem"))
      key_der = private_key_der(dir)

      key_body =
        key |> String.split("\n") |> Enum.find(&String.match?(&1, ~r/^[A-Za-z0-9+\/]{40}/))

      p12 = File.read!(Path.join(dir, "client.p12"))
      Process.flag(:trap_exit, true)

      for {filename, contents} <- [
            {"partial.pem", cert <> String.replace(key, "-----END PRIVATE KEY-----", "")},
            {"garbled.pem",
             cert <>
               "-----BEGIN PRIVATE KEY-----\n" <> key_body <> "!!\n-----END PRIVATE KEY-----\n"},
            {"truncated.p12", binary_part(p12, 0, div(byte_size(p12), 2))}
          ] do
        path = Path.join(dir, filename)
        File.write!(path, contents)

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            assert {:error, {%ArgumentError{message: message}, stack}} =
                     start_invalid(
                       "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"
                     )

            assert message == "invalid client certificate or password for #{path}"
            refute_key_material(inspect({message, stack}, limit: :infinity), key_der)
            refute inspect({message, stack}, limit: :infinity) =~ key_body
            Logger.flush()
          end)

        refute_key_material(log, key_der)
        refute log =~ key_body
      end
    end

    test "rejects a missing certificate instead of connecting without one" do
      path = "/missing/chronicle-client.p12"
      connection_string = "chronicle://localhost:35000?certificatePath=#{path}"

      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(connection_string)

      assert message =~ path
    end

    @tag :tmp_dir
    test "rejects client certificates when TLS is disabled", %{tmp_dir: tmp_dir} do
      path = certificate_fixture(tmp_dir)

      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(
                 "chronicle://localhost:35000?disableTls=true&certificatePath=#{URI.encode_www_form(path)}"
               )

      assert message =~ "TLS is disabled"
    end

    test "rejects a certificate password with an empty path when TLS is disabled" do
      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid(
                 "chronicle://localhost:35000?disableTls=true&certificatePath=&certificatePassword=secret"
               )

      assert message =~ "certificatePassword requires a certificatePath"
    end

    test "rejects a certificate password without a certificate path" do
      assert {:error, {%ArgumentError{message: message}, _}} =
               start_invalid("chronicle://localhost:35000?certificatePassword=secret")

      assert message =~ "certificatePath"
    end
  end

  @tag :tmp_dir
  @tag capture_log: true
  test "the OAuth token provider presents the configured client certificate", %{tmp_dir: tmp_dir} do
    path = certificate_fixture(tmp_dir)
    cert_path = Path.join(tmp_dir, "cert.pem")
    key_path = Path.join(tmp_dir, "key.pem")

    [{:Certificate, expected_peer, _}] = :public_key.pem_decode(File.read!(cert_path))

    verify_peer = fn _cert, der, event, state ->
      case event do
        {:bad_cert, :selfsigned_peer} ->
          if der == expected_peer, do: {:valid, state}, else: {:fail, :unexpected_peer}

        {:bad_cert, _} = reason ->
          {:fail, reason}

        {:extension, _} ->
          {:unknown, state}

        _ ->
          {:valid, state}
      end
    end

    {:ok, listener} =
      :ssl.listen(0,
        certfile: cert_path,
        keyfile: key_path,
        cacertfile: cert_path,
        verify: :verify_peer,
        verify_fun: {verify_peer, nil},
        fail_if_no_peer_cert: true,
        alpn_preferred_protocols: ["h2"],
        active: false
      )

    {:ok, {_, port}} = :ssl.sockname(listener)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)

        result =
          with {:ok, tls} <- :ssl.handshake(socket, 5_000),
               {:ok, peer} <- :ssl.peercert(tls) do
            send(parent, {:oauth_peer, peer})
            :ssl.close(tls)
            :ok
          end

        :ssl.close(listener)
        result
      end)

    conn =
      start(
        connection_string:
          "chronicle://user:pass@localhost:#{port}?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret",
        connect_fun: fn _target, opts ->
          send(parent, {:grpc_opts, opts})
          {:ok, channel_with_conn(parent)}
        end,
        auto_connect: true
      )

    assert :ok = Connection.connect(conn, 1_000)
    assert_receive {:grpc_opts, opts}
    assert opts[:cred].ssl[:cert]
    [{Chronicle.Connections.AuthInterceptor, provider: provider} | _] = opts[:interceptors]
    assert %{} = Chronicle.Connections.TokenProvider.authorization_headers(provider)
    assert Process.alive?(provider)
    assert_receive {:oauth_peer, peer}, 5_000
    assert peer == opts[:cred].ssl[:cert]
    assert :ok = Task.await(server, 6_000)
  end

  @tag :tmp_dir
  test "rejects unsupported adapter and credential before dialing", %{tmp_dir: tmp_dir} do
    path = certificate_fixture(tmp_dir)

    cs =
      "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"

    Process.flag(:trap_exit, true)

    for opts <- [[adapter: GRPC.Client.Adapters.Gun], [cred: :invalid]] do
      assert {:error, {%ArgumentError{}, _}} =
               Connection.start_link(
                 connection_string: cs,
                 grpc_options: opts,
                 auto_connect: false
               )
    end
  end

  @tag :tmp_dir
  test "rejects conflicting identity from credential or Mint transport", %{tmp_dir: tmp_dir} do
    path = certificate_fixture(tmp_dir)

    cs =
      "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"

    Process.flag(:trap_exit, true)

    for opts <- [
          [cred: GRPC.Credential.new(ssl: [certs_keys: []])],
          [adapter_opts: [transport_opts: [certs_keys: []]]]
        ] do
      assert {:error, {%ArgumentError{message: message}, _}} =
               Connection.start_link(
                 connection_string: cs,
                 grpc_options: opts,
                 auto_connect: false
               )

      assert message =~ "conflicts"
    end
  end

  @tag :tmp_dir
  test "rejects every adapter-level server verification option with a client identity", %{
    tmp_dir: tmp_dir
  } do
    path = certificate_fixture(tmp_dir)

    cs =
      "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"

    Process.flag(:trap_exit, true)

    for option <- [
          :verify,
          :verify_fun,
          :partial_chain,
          :cacerts,
          :cacertfile,
          :customize_hostname_check,
          :server_name_indication
        ] do
      assert {:error, {%ArgumentError{message: message}, _}} =
               Connection.start_link(
                 connection_string: cs,
                 grpc_options: [adapter_opts: [transport_opts: [{option, :caller_setting}]]],
                 auto_connect: false
               )

      assert message =~ "adapter_opts transport_opts server verification"
    end
  end

  @tag :tmp_dir
  test "rejects additional adapter-level certificate policies before dialing", %{tmp_dir: tmp_dir} do
    path = certificate_fixture(tmp_dir)

    cs =
      "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"

    parent = self()
    Process.flag(:trap_exit, true)

    for {option, value} <- [
          depth: 1,
          crl_check: :peer,
          crl_cache: {:ssl_crl_cache, {:internal, []}},
          cert_policy_opts: [explicit_policy: true],
          allow_any_ca_purpose: true,
          certificate_authorities: true,
          stapling: :staple,
          signature_algs: [{:sha256, :rsa}],
          signature_algs_cert: [:rsa_pkcs1_sha256]
        ] do
      assert {:error, {%ArgumentError{message: message}, _}} =
               Connection.start_link(
                 connection_string: cs,
                 grpc_options: [adapter_opts: [transport_opts: [{option, value}]]],
                 connect_fun: fn _, _ ->
                   send(parent, :dialed)
                   {:ok, %{}}
                 end
               )

      assert message =~ "adapter_opts transport_opts server verification"
      refute_received :dialed
    end
  end

  test "empty certificate password without a path is absent" do
    conn = start(connection_string: "chronicle://localhost?certificatePassword=")
    refute Connection.connected?(conn)
  end

  test "empty certificate path is absent" do
    conn = start(connection_string: "chronicle://localhost:35000?certificatePath=")
    refute Connection.connected?(conn)
  end

  test "rejects a certificate password with an empty certificate path" do
    assert {:error, {%ArgumentError{message: message}, _}} =
             start_invalid(
               "chronicle://localhost:35000?certificatePath=&certificatePassword=secret"
             )

    assert message =~ "certificatePath"
  end

  @tag :tmp_dir
  test "accepts an encrypted PEM key with a UTF-8 password", %{tmp_dir: tmp_dir} do
    certificate_fixture(tmp_dir)
    encrypted = Path.join(tmp_dir, "unicode-key.pem")
    bundle = Path.join(tmp_dir, "unicode.pem")

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "pkcs8",
          "-topk8",
          "-in",
          Path.join(tmp_dir, "key.pem"),
          "-out",
          encrypted,
          "-passout",
          "pass:pässword"
        ],
        stderr_to_stdout: true
      )

    File.write!(bundle, File.read!(Path.join(tmp_dir, "cert.pem")) <> File.read!(encrypted))

    cs =
      "chronicle://localhost:35000?certificatePath=#{URI.encode_www_form(bundle)}&certificatePassword=#{URI.encode_www_form("pässword")}"
      |> ConnectionString.parse()

    assert [cert: _, key: %{algorithm: :rsa}] = ClientCertificate.load!(cs)
  end

  @tag :tmp_dir
  test "accepts PEM preamble and whitespace", %{tmp_dir: tmp_dir} do
    certificate_fixture(tmp_dir)
    bundle = Path.join(tmp_dir, "preamble.pem")

    File.write!(
      bundle,
      " \nBag Attributes\n    friendlyName: client\n" <>
        File.read!(Path.join(tmp_dir, "cert.pem")) <> File.read!(Path.join(tmp_dir, "key.pem"))
    )

    assert [cert: _, key: _] =
             ClientCertificate.load!(
               ConnectionString.parse(
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
               )
             )
  end

  @tag :tmp_dir
  test "loads a PKCS#12 export using legacy encryption", %{tmp_dir: tmp_dir} do
    certificate_fixture(tmp_dir)
    legacy = Path.join(tmp_dir, "legacy.p12")

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "pkcs12",
          "-export",
          "-legacy",
          "-certpbe",
          "PBE-SHA1-RC2-40",
          "-inkey",
          Path.join(tmp_dir, "key.pem"),
          "-in",
          Path.join(tmp_dir, "cert.pem"),
          "-out",
          legacy,
          "-passout",
          "pass:secret"
        ],
        stderr_to_stdout: true
      )

    cs =
      ConnectionString.parse(
        "chronicle://localhost?certificatePath=#{URI.encode_www_form(legacy)}&certificatePassword=secret"
      )

    assert [cert: _, key: _] = ClientCertificate.load!(cs)
  end

  @tag :tmp_dir
  test "connected status redacts the channel credential, headers, message and log", %{
    tmp_dir: tmp_dir
  } do
    path = certificate_fixture(tmp_dir)
    secret = "unique-private-key-#{System.unique_integer([:positive])}"

    channel = %GRPC.Channel{
      cred: GRPC.Credential.new(ssl: [key: {:PrivateKeyInfo, secret}]),
      headers: [{"api-key", "unique-api-key-secret"}]
    }

    conn =
      start(
        connection_string:
          "chronicle://localhost?apiKey=unique-api-key-secret&certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret",
        connect_fun: fn _target, _opts -> {:ok, channel} end,
        disconnect_fun: fn _ -> :ok end,
        auto_connect: true
      )

    assert :ok = Connection.connect(conn, 1_000)
    assert {:ok, ^channel} = Connection.channel(conn)
    status = :sys.get_status(conn) |> inspect(limit: :infinity)
    refute status =~ secret
    refute status =~ "unique-api-key-secret"
    assert status =~ "connected"

    state = :sys.get_state(conn)

    formatted =
      Connection.format_status(%{
        state: state,
        message: {:connect_result, {:ok, channel}},
        log: [{:connect_result, {:ok, channel}}]
      })
      |> inspect(limit: :infinity)

    refute formatted =~ secret
    refute formatted =~ "unique-api-key-secret"
  end

  @tag :tmp_dir
  test "a malformed gRPC trailer crash never logs the private key", %{tmp_dir: dir} do
    certificate_fixture(dir)
    key_der = private_key_der(dir)
    parent = self()

    connection =
      start(
        connection_string:
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(Path.join(dir, "client.p12"))}&certificatePassword=secret",
        connect_fun: fn _target, opts ->
          {:ok, %GRPC.Channel{cred: opts[:cred]}}
        end,
        disconnect_fun: fn _ -> :ok end,
        auto_connect: true
      )

    assert :ok = Connection.connect(connection, 1_000)
    {:ok, channel} = Connection.channel(connection)
    key = channel.cred.ssl[:key]
    assert %{sign_fun: sign_fun} = key
    assert is_function(sign_fun, 3)
    assert {:env, [signer]} = :erlang.fun_info(sign_fun, :env)
    assert is_pid(signer)

    Process.flag(:trap_exit, true)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, response} =
          StreamResponseProcess.start_link(%GRPC.Client.Stream{channel: channel}, false)

        monitor = Process.monitor(response)

        assert {:error, _reason} =
                 StreamResponseProcess.consume(response, :trailers, [
                   {"grpc-status", "not-an-integer"}
                 ])

        assert_receive {:DOWN, ^monitor, :process, ^response, _reason}, 2_000
        Logger.flush()
        send(parent, :crash_captured)
      end)

    assert_receive :crash_captured
    assert log =~ "StreamResponseProcess"
    assert log =~ "ArgumentError"
    assert log =~ "GRPC.Channel"
    refute_key_material(log, key_der)
  end

  @tag :tmp_dir
  test "a Connection callback crash redacts reason stack arguments", %{tmp_dir: dir} do
    certificate_fixture(dir)
    key_der = private_key_der(dir)
    Process.flag(:trap_exit, true)

    connection =
      start(
        connection_string:
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(Path.join(dir, "client.p12"))}&certificatePassword=secret",
        auto_connect: false
      )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        monitor = Process.monitor(connection)
        assert catch_exit(GenServer.call(connection, :unexpected_call))
        assert_receive {:DOWN, ^monitor, :process, ^connection, _reason}, 2_000
        Logger.flush()
      end)

    assert log =~ "Chronicle.Connections.Connection"
    assert log =~ "handle_call/3"
    refute log =~ "client_certificate: ["
    refute_key_material(log, key_der)
  end

  @tag :tmp_dir
  test "a signer failure restarts its supervised connection with a fresh identity", %{
    tmp_dir: dir
  } do
    certificate_fixture(dir)
    path = Path.join(dir, "client.p12")
    parent = self()

    {:ok, _supervisor} =
      Supervisor.start_link(
        [
          {Connection,
           connection_string:
             "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret",
           connect_fun: fn _target, opts ->
             send(parent, {:identity, opts[:cred].ssl})
             {:ok, %{}}
           end,
           disconnect_fun: fn _ -> :ok end,
           reconnect_base_delay: 10,
           auto_connect: true,
           name: :signer_recovery_connection}
        ],
        strategy: :one_for_one
      )

    connection = Process.whereis(:signer_recovery_connection)
    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:identity, first_ssl}, 2_000
    signer = signer_pid(first_ssl)
    old_connection = Process.monitor(connection)
    Process.exit(signer, :kill)
    assert_receive {:DOWN, ^old_connection, :process, ^connection, _}, 2_000

    new_connection = await_named_connection(:signer_recovery_connection, connection)
    assert :ok = Connection.connect(new_connection, 2_000)
    assert_receive {:identity, next_ssl}, 2_000
    assert signer_pid(next_ssl) != signer
    refute Process.alive?(signer)
    assert next_ssl[:cert] == first_ssl[:cert]
    assert is_binary(next_ssl[:key].sign_fun.("challenge", :sha256, []))
    assert_identity_handshake(next_ssl, dir)
  end

  @tag :tmp_dir
  test "signers belong to their own connection and stop on normal shutdown", %{tmp_dir: dir} do
    certificate_fixture(dir)
    path = Path.join(dir, "client.p12")
    parent = self()

    connect_fun = fn target, opts ->
      send(parent, {:identity, target, opts[:cred].ssl})
      {:ok, %{}}
    end

    cs =
      "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}&certificatePassword=secret"

    first = start(connection_string: cs, connect_fun: connect_fun, auto_connect: true)

    second =
      start(
        connection_string: String.replace(cs, "localhost", "127.0.0.1"),
        connect_fun: connect_fun,
        auto_connect: true
      )

    assert :ok = Connection.connect(first, 2_000)
    assert :ok = Connection.connect(second, 2_000)
    assert_receive {:identity, "ipv4:localhost:35000", first_ssl}, 2_000
    assert_receive {:identity, "ipv4:127.0.0.1:35000", second_ssl}, 2_000
    first_signer = signer_pid(first_ssl)
    second_signer = signer_pid(second_ssl)
    assert first_signer != second_signer
    monitor = Process.monitor(first_signer)
    assert :ok = Connection.disconnect(first)
    assert_receive {:DOWN, ^monitor, :process, ^first_signer, _}, 2_000
    assert Process.alive?(second_signer)
    assert is_binary(second_ssl[:key].sign_fun.("challenge", :sha256, []))
    assert :ok = Connection.disconnect(second)
  end

  defp assert_identity_handshake(ssl, dir) do
    certfile = Path.join(dir, "cert.pem")
    [{:Certificate, expected, _}] = :public_key.pem_decode(File.read!(certfile))

    verify_peer = fn _cert, event, state ->
      case event do
        {:bad_cert, :selfsigned_peer} -> {:valid, state}
        {:bad_cert, reason} -> {:fail, reason}
        {:extension, _} -> {:unknown, state}
        _ -> {:valid, state}
      end
    end

    {:ok, listener} =
      :ssl.listen(0,
        certfile: certfile,
        keyfile: Path.join(dir, "key.pem"),
        cacertfile: certfile,
        verify: :verify_peer,
        verify_fun: {verify_peer, nil},
        fail_if_no_peer_cert: true,
        active: false,
        reuseaddr: true
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)
        {:ok, tls} = :ssl.handshake(socket, 5_000)
        peer = :ssl.peercert(tls)
        :ssl.close(tls)
        :ssl.close(listener)
        peer
      end)

    assert {:ok, socket} =
             :ssl.connect(
               ~c"localhost",
               port,
               [verify: :verify_none, active: false] ++ ssl,
               5_000
             )

    :ssl.close(socket)
    assert {:ok, expected} == Task.await(server, 6_000)
  end

  defp signer_pid(ssl) do
    assert {:env, [pid]} = :erlang.fun_info(ssl[:key].sign_fun, :env)
    pid
  end

  defp await_named_connection(name, previous) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    await_named_connection(name, previous, deadline)
  end

  defp await_named_connection(name, previous, deadline) do
    case Process.whereis(name) do
      pid when is_pid(pid) and pid != previous ->
        pid

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "connection did not restart"
        Process.sleep(10)
        await_named_connection(name, previous, deadline)
    end
  end

  defp private_key_der(dir) do
    {pem, 0} =
      System.cmd(
        "openssl",
        ["pkcs12", "-in", Path.join(dir, "client.p12"), "-nodes", "-passin", "pass:secret"],
        stderr_to_stdout: true
      )

    {type, der, :not_encrypted} =
      pem
      |> :public_key.pem_decode()
      |> Enum.find(fn {type, _, _} -> type in [:RSAPrivateKey, :PrivateKeyInfo] end)

    assert type in [:RSAPrivateKey, :PrivateKeyInfo]
    der
  end

  defp refute_key_material(log, der) do
    for bytes <- [der, binary_part(der, 0, min(byte_size(der), 32))] do
      refute log =~ bytes
      refute log =~ Base.encode64(bytes)
      refute log =~ Base.encode16(bytes)
      refute log =~ Base.encode16(bytes, case: :lower)
      refute log =~ Enum.join(:binary.bin_to_list(bytes), ", ")
    end
  end

  test "an unexpected cast never logs a connected channel's API key" do
    secret = "private-api-cast-secret"
    Process.flag(:trap_exit, true)

    connection =
      start(
        connection_string: "chronicle://localhost?apiKey=#{secret}",
        connect_fun: fn _target, opts -> {:ok, %{headers: opts[:headers]}} end,
        disconnect_fun: fn _ -> :ok end,
        auto_connect: true
      )

    assert :ok = Connection.connect(connection, 1_000)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        monitor = Process.monitor(connection)
        GenServer.cast(connection, :unexpected_cast)
        assert_receive {:DOWN, ^monitor, :process, ^connection, _}, 2_000
        Logger.flush()
      end)

    assert log =~ "handle_cast/2"
    refute log =~ secret
  end

  test "redacts secrets from inspected and process status" do
    cs =
      ConnectionString.parse(
        "chronicle://user:private-pass@localhost?apiKey=private-api&certificatePassword=private-cert"
      )

    inspected = inspect(cs)
    refute inspected =~ "private-pass"
    refute inspected =~ "private-api"
    refute inspected =~ "private-cert"

    conn =
      start(
        connection_string: "chronicle://user:private-pass@localhost?apiKey=private-api",
        grpc_options: [headers: [{"secret", "private-header"}]]
      )

    status = :sys.get_status(conn) |> inspect(limit: :infinity)
    refute status =~ "private-pass"
    refute status =~ "private-api"
    refute status =~ "private-header"
  end

  defp start_invalid(connection_string) do
    Process.flag(:trap_exit, true)
    Connection.start_link(connection_string: connection_string, auto_connect: false)
  end

  defp certificate_fixture(tmp_dir) do
    key = Path.join(tmp_dir, "key.pem")
    cert = Path.join(tmp_dir, "cert.pem")
    path = Path.join(tmp_dir, "client.p12")

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-days",
          "1",
          "-subj",
          "/CN=localhost",
          "-keyout",
          key,
          "-out",
          cert
        ],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "pkcs12",
          "-export",
          "-inkey",
          key,
          "-in",
          cert,
          "-out",
          path,
          "-passout",
          "pass:secret"
        ],
        stderr_to_stdout: true
      )

    path
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
