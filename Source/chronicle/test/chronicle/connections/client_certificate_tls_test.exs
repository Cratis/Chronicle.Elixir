# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ClientCertificateTlsTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.{Auth, ClientCertificate, Connection, ConnectionString}

  @tag :tmp_dir
  test "a PEM client bundle presents its intermediate to a root-trusting server", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    pem = Path.join(dir, "client-chain.pem")

    File.write!(
      pem,
      File.read!(fixtures.client_cert) <>
        File.read!(fixtures.intermediate_cert) <> File.read!(fixtures.client_key)
    )

    assert_handshake(pem, fixtures)
  end

  @tag :tmp_dir
  test "a PKCS#12 client bundle presents its intermediate to a root-trusting server", %{
    tmp_dir: dir
  } do
    fixtures = chain_fixture(dir)
    path = Path.join(dir, "client-chain.p12")

    openssl([
      "pkcs12",
      "-export",
      "-inkey",
      fixtures.client_key,
      "-in",
      fixtures.client_cert,
      "-certfile",
      fixtures.intermediate_cert,
      "-out",
      path,
      "-passout",
      "pass:"
    ])

    assert_handshake(path, fixtures)
  end

  @tag :tmp_dir
  test "the Mint adapter presents the configured client identity to the server", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    bundle = Path.join(dir, "mint-client.pem")

    File.write!(
      bundle,
      File.read!(fixtures.client_cert) <>
        File.read!(fixtures.intermediate_cert) <> File.read!(fixtures.client_key)
    )

    cs = "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
    identity = ClientCertificate.load!(ConnectionString.parse(cs))

    {:ok, listener} =
      :ssl.listen(0,
        certfile: fixtures.server_cert,
        keyfile: fixtures.server_key,
        cacertfile: fixtures.root_cert,
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        alpn_preferred_protocols: ["h2"],
        active: false,
        reuseaddr: true
      )

    {:ok, {_, port}} = :ssl.sockname(listener)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)

        result =
          case :ssl.handshake(socket, 5_000) do
            {:ok, tls} ->
              peer = :ssl.peercert(tls)
              send(parent, {:mint_peer, peer})
              :ssl.close(tls)
              peer

            error ->
              send(parent, {:mint_peer, error})
              error
          end

        receive do
          :close -> :ok
        after
          6_000 -> :ok
        end

        :ssl.close(listener)
        result
      end)

    # Capture the credential assembled by Chronicle, then dial with the real
    # Mint adapter (not the connect_fun seam). The adapter itself owns the TLS
    # handshake and the server observes the actual client certificate.
    {:ok, connection} =
      Connection.start_link(
        connection_string:
          "chronicle://localhost:#{port}?certificatePath=#{URI.encode_www_form(bundle)}",
        connect_fun: fn _target, opts ->
          send(parent, {:grpc_opts, opts})
          {:ok, %{}}
        end,
        disconnect_fun: fn _ -> :ok end,
        auto_connect: true
      )

    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:grpc_opts, opts}

    channel = %GRPC.Channel{host: "localhost", port: port, scheme: "https", cred: opts[:cred]}

    # Safe module options do not replace the transport identity. On macOS Mint
    # may return a socket-option error after TLS, so assert the peer on the server.
    result = GRPC.Client.Adapters.Mint.connect(channel, config_options: [client_settings: []])
    assert_receive {:mint_peer, {:ok, peer}}, 5_000
    assert peer == hd(identity[:cert])
    if match?({:ok, _}, result), do: GRPC.Client.Adapters.Mint.disconnect(elem(result, 1))
    Connection.disconnect(connection)
    send(server.pid, :close)
    assert {:ok, ^peer} = Task.await(server, 7_000)

    # Mint merges these options AFTER credential SSL settings. Accepting even
    # a harmless-looking transport_opts discards the entire client identity.
    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _}} =
             Connection.start_link(
               connection_string: cs,
               grpc_options: [
                 adapter_opts: [config_options: [transport_opts: [verify: :verify_none]]]
               ],
               auto_connect: false
             )

    assert message =~ "Mint"
    assert message =~ "transport_opts"
  end

  @tag :tmp_dir
  test "adapter-level verification still rejects a CA-trusted server without a client identity",
       %{
         tmp_dir: dir
       } do
    fixtures = chain_fixture(dir)
    parent = self()

    reject_server = fn _cert, _der, event, state ->
      send(parent, {:verify_event, event})

      case event do
        :valid_peer -> {:fail, :caller_rejected_server}
        {:bad_cert, _} = reason -> {:fail, reason}
        {:extension, _} -> {:unknown, state}
        _ -> {:valid, state}
      end
    end

    adapter_opts = [transport_opts: [verify_fun: {reject_server, nil}]]
    assert_no_identity_handshake(fixtures, adapter_opts, false)
    assert_receive {:verify_event, :valid_peer}

    bundle = Path.join(dir, "unrelated-client.pem")
    File.write!(bundle, File.read!(fixtures.client_cert) <> File.read!(fixtures.client_key))

    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _}} =
             Connection.start_link(
               connection_string:
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}&skipTlsValidation=false",
               grpc_options: [adapter_opts: adapter_opts],
               auto_connect: false
             )

    assert message =~ "adapter_opts"
    assert message =~ "GRPC.Credential"
  end

  @tag :tmp_dir
  test "adapter-level partial_chain remains effective without an identity and rejects with one",
       %{
         tmp_dir: dir
       } do
    fixtures = chain_fixture(dir)
    parent = self()
    [{:Certificate, root, _}] = :public_key.pem_decode(File.read!(fixtures.root_cert))
    decoded_root = :public_key.pkix_decode_cert(root, :plain)

    callback = fn chain ->
      send(parent, :adapter_partial_chain_called)
      Mint.Core.Transport.SSL.partial_chain([decoded_root], chain)
    end

    adapter_opts = [transport_opts: [partial_chain: callback]]
    assert_no_identity_handshake(fixtures, adapter_opts, true)
    assert_receive :adapter_partial_chain_called

    bundle = Path.join(dir, "unrelated-client.pem")
    File.write!(bundle, File.read!(fixtures.client_cert) <> File.read!(fixtures.client_key))

    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _}} =
             Connection.start_link(
               connection_string:
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}&skipTlsValidation=false",
               grpc_options: [adapter_opts: adapter_opts],
               auto_connect: false
             )

    assert message =~ "adapter_opts"
    assert message =~ "GRPC.Credential"
  end

  @tag :tmp_dir
  test "rejects application-level Mint transport overrides before dialing", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    bundle = Path.join(dir, "app-cert.pem")
    File.write!(bundle, File.read!(fixtures.server_cert) <> File.read!(fixtures.server_key))

    previous = Application.get_env(:grpc, GRPC.Client.Adapters.Mint)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:grpc, GRPC.Client.Adapters.Mint),
        else: Application.put_env(:grpc, GRPC.Client.Adapters.Mint, previous)
    end)

    Application.put_env(:grpc, GRPC.Client.Adapters.Mint, transport_opts: [verify: :verify_none])
    Process.flag(:trap_exit, true)

    assert {:error, {%ArgumentError{message: message}, _}} =
             Connection.start_link(
               connection_string:
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}",
               auto_connect: false
             )

    assert message =~ "Mint module transport_opts"
  end

  @tag :tmp_dir
  test "an untrusted server is accepted only when its certificate matches the pinned identity", %{
    tmp_dir: dir
  } do
    fixtures = chain_fixture(dir)
    server_bundle = Path.join(dir, "server-bundle.pem")

    File.write!(
      server_bundle,
      File.read!(fixtures.server_cert) <> File.read!(fixtures.server_key)
    )

    pinned =
      ClientCertificate.load!(
        ConnectionString.parse(
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(server_bundle)}"
        )
      )

    other_bundle = Path.join(dir, "other-bundle.pem")
    File.write!(other_bundle, File.read!(fixtures.client_cert) <> File.read!(fixtures.client_key))

    other =
      ClientCertificate.load!(
        ConnectionString.parse(
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(other_bundle)}"
        )
      )

    for {identity, should_connect} <- [{other, false}, {pinned, true}] do
      {:ok, listener} =
        :ssl.listen(0,
          certfile: fixtures.server_cert,
          keyfile: fixtures.server_key,
          verify: :verify_none,
          active: false,
          reuseaddr: true
        )

      {:ok, {_, port}} = :ssl.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5_000)
          result = :ssl.handshake(socket, 5_000)

          case result do
            {:ok, tls} -> :ssl.close(tls)
            _ -> :ok
          end

          :ssl.close(listener)
        end)

      ssl_opts =
        [verify: :verify_peer, cacerts: [], active: false] ++
          ClientCertificate.server_verify_options(identity) ++ identity

      case :ssl.connect(~c"localhost", port, ssl_opts, 5_000) do
        {:ok, tls} ->
          assert should_connect
          :ssl.close(tls)

        {:error, _} ->
          refute should_connect
      end

      Task.await(server, 6_000)
    end
  end

  @tag :tmp_dir
  test "pinning does not override a credential's failed CRL verification", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    leaf = Path.join(dir, "crl-server.pem")
    bundle = Path.join(dir, "crl-server-bundle.pem")
    ext = Path.join(dir, "crl-server.ext")

    File.write!(
      ext,
      File.read!(fixtures.server_ext) <>
        "crlDistributionPoints=URI:http://127.0.0.1:1/missing.crl\n"
    )

    openssl([
      "x509",
      "-req",
      "-in",
      fixtures.server_csr,
      "-CA",
      fixtures.root_cert,
      "-CAkey",
      fixtures.root_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      ext,
      "-out",
      leaf
    ])

    File.write!(bundle, File.read!(leaf) <> File.read!(fixtures.server_key))

    identity =
      ClientCertificate.load!(
        ConnectionString.parse(
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
        )
      )

    [{:Certificate, root, _}] = :public_key.pem_decode(File.read!(fixtures.root_cert))
    trust = [verify: :verify_peer, cacerts: [root], crl_check: :peer, active: false]
    # A matching pin must not bypass a caller's CRL policy by becoming a
    # trusted leaf before OTP can check revocation.
    assert [] == ClientCertificate.server_verify_options(identity, trust)
    assert [] == ClientCertificate.server_verify_options(identity, depth: 1)
    assert [] == ClientCertificate.server_verify_options(identity, stapling: :staple)
    pin_options = ClientCertificate.server_verify_options(identity)
    {verify_fun, false} = pin_options[:verify_fun]

    for reason <- [
          :certificate_revoked,
          :certificate_expired,
          :missing_ocsp_staple,
          {:bad_crls, :no_relevant_crls}
        ] do
      assert {:fail, {:bad_cert, ^reason}} =
               verify_fun.(nil, identity[:cert], {:bad_cert, reason}, false)
    end

    for {mode, extra} <- [
          baseline: [],
          credential: ClientCertificate.server_verify_options(identity, trust)
        ] do
      {:ok, listener} =
        :ssl.listen(0,
          certfile: leaf,
          keyfile: fixtures.server_key,
          verify: :verify_none,
          active: false,
          reuseaddr: true
        )

      {:ok, {_, port}} = :ssl.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5_000)
          result = :ssl.handshake(socket, 5_000)
          if match?({:ok, _}, result), do: :ssl.close(elem(result, 1))
          :ssl.close(listener)
          result
        end)

      result = :ssl.connect(~c"localhost", port, trust ++ extra, 5_000)
      if match?({:ok, _}, result), do: :ssl.close(elem(result, 1))

      assert {:error, reason} = result,
             "#{mode} unexpectedly accepted a certificate with an unverifiable CRL"

      assert inspect(reason) =~ "bad_crls"
      Task.await(server, 6_000)
    end
  end

  @tag :tmp_dir
  test "mutual TLS keeps a custom CA callback and its trusted intermediate", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    leaf = sign_server_with_intermediate(dir, fixtures)
    server_chain = Path.join(dir, "trusted-intermediate-chain.pem")
    File.write!(server_chain, File.read!(leaf) <> File.read!(fixtures.intermediate_cert))

    identity_path = Path.join(dir, "unrelated-identity.pem")

    File.write!(
      identity_path,
      File.read!(fixtures.server_cert) <> File.read!(fixtures.server_key)
    )

    parent = self()
    [{:Certificate, ca, _}] = :public_key.pem_decode(File.read!(fixtures.intermediate_cert))
    decoded_ca = :public_key.pkix_decode_cert(ca, :plain)

    callback = fn chain ->
      send(parent, :custom_partial_chain_called)
      Mint.Core.Transport.SSL.partial_chain([decoded_ca], chain)
    end

    trust = [verify: :verify_peer, cacerts: [ca], partial_chain: callback]
    assert_ca_handshake(dir, fixtures, identity_path, server_chain, trust)
    assert_receive :custom_partial_chain_called
  end

  @tag :tmp_dir
  test "mutual TLS retains Mint's public-key anchor for a cross-signed intermediate", %{
    tmp_dir: dir
  } do
    fixtures = chain_fixture(dir)
    leaf = sign_server_with_intermediate(dir, fixtures)
    other_root = Path.join(dir, "other-root.pem")
    other_key = Path.join(dir, "other-root.key")

    openssl([
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-days",
      "1",
      "-subj",
      "/CN=Other Root",
      "-addext",
      "basicConstraints=critical,CA:TRUE",
      "-keyout",
      other_key,
      "-out",
      other_root
    ])

    cross_signed = Path.join(dir, "cross-signed.pem")

    openssl([
      "x509",
      "-req",
      "-in",
      Path.join(dir, "intermediate.csr"),
      "-CA",
      other_root,
      "-CAkey",
      other_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      Path.join(dir, "intermediate.ext"),
      "-out",
      cross_signed
    ])

    server_chain = Path.join(dir, "cross-signed-chain.pem")
    File.write!(server_chain, File.read!(leaf) <> File.read!(cross_signed))
    identity_path = Path.join(dir, "unrelated-identity.pem")

    File.write!(
      identity_path,
      File.read!(fixtures.server_cert) <> File.read!(fixtures.server_key)
    )

    [{:Certificate, trusted, _}] = :public_key.pem_decode(File.read!(fixtures.intermediate_cert))

    assert_ca_handshake(dir, fixtures, identity_path, server_chain,
      verify: :verify_peer,
      cacerts: [trusted]
    )
  end

  @tag :tmp_dir
  test "pin checks the leaf, not the chain", %{
    tmp_dir: dir
  } do
    fixtures = chain_fixture(dir)
    # Sign a serverAuth leaf with an otherwise untrusted intermediate.
    chained_leaf = Path.join(dir, "chained-leaf.pem")

    openssl([
      "x509",
      "-req",
      "-in",
      fixtures.server_csr,
      "-CA",
      fixtures.intermediate_cert,
      "-CAkey",
      fixtures.intermediate_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      fixtures.server_ext,
      "-out",
      chained_leaf
    ])

    pinned_bundle = Path.join(dir, "pinned.pem")
    File.write!(pinned_bundle, File.read!(chained_leaf) <> File.read!(fixtures.server_key))
    ca_bundle = Path.join(dir, "pinned-ca.pem")

    File.write!(
      ca_bundle,
      File.read!(fixtures.intermediate_cert) <> File.read!(fixtures.intermediate_key)
    )

    for {bundle, succeeds?} <- [{pinned_bundle, true}, {ca_bundle, false}] do
      identity =
        ClientCertificate.load!(
          ConnectionString.parse(
            "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
          )
        )

      server_chain = Path.join(dir, "server-chain.pem")

      # Without the root, OTP reaches the pinned intermediate before checking
      # the peer, so this must exercise the leaf-mismatch branch.
      File.write!(
        server_chain,
        File.read!(chained_leaf) <> File.read!(fixtures.intermediate_cert)
      )

      {:ok, listener} =
        :ssl.listen(0,
          certfile: server_chain,
          keyfile: fixtures.server_key,
          verify: :verify_none,
          active: false,
          reuseaddr: true
        )

      {:ok, {_, port}} = :ssl.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5_000)
          result = :ssl.handshake(socket, 5_000)
          if match?({:ok, _}, result), do: :ssl.close(elem(result, 1))
          :ssl.close(listener)
        end)

      result =
        :ssl.connect(
          ~c"localhost",
          port,
          [verify: :verify_peer, cacerts: [], active: false] ++
            ClientCertificate.server_verify_options(identity),
          5_000
        )

      if succeeds? do
        assert {:ok, tls} = result
        :ssl.close(tls)
      else
        assert {:error, reason} = result
        assert inspect(reason) =~ "pinned_certificate_mismatch"
      end

      Task.await(server, 6_000)
    end
  end

  @tag :tmp_dir
  test "selects the private-key owner even when the intermediate appears first", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    path = Path.join(dir, "intermediate-first.pem")

    File.write!(
      path,
      File.read!(fixtures.intermediate_cert) <>
        File.read!(fixtures.client_cert) <> File.read!(fixtures.client_key)
    )

    identity =
      ClientCertificate.load!(
        ConnectionString.parse(
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}"
        )
      )

    [{:Certificate, leaf, _}] = :public_key.pem_decode(File.read!(fixtures.client_cert))
    assert hd(identity[:cert]) == leaf
    assert_handshake(path, fixtures)
  end

  @tag :tmp_dir
  test "rejects a private key that owns none of the certificates", %{tmp_dir: dir} do
    fixtures = chain_fixture(dir)
    path = Path.join(dir, "mismatched.pem")
    File.write!(path, File.read!(fixtures.client_cert) <> File.read!(fixtures.server_key))

    assert_raise ArgumentError, ~r/invalid client certificate/, fn ->
      ClientCertificate.load!(
        ConnectionString.parse(
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}"
        )
      )
    end
  end

  @tag :tmp_dir
  test "matches an EC private key to its certificate", %{tmp_dir: dir} do
    cert = Path.join(dir, "ec.pem")
    key = Path.join(dir, "ec.key")
    bundle = Path.join(dir, "ec-bundle.pem")

    openssl([
      "req",
      "-x509",
      "-newkey",
      "ec",
      "-pkeyopt",
      "ec_paramgen_curve:prime256v1",
      "-nodes",
      "-days",
      "1",
      "-subj",
      "/CN=EC Client",
      "-keyout",
      key,
      "-out",
      cert
    ])

    File.write!(bundle, File.read!(cert) <> File.read!(key))

    assert [cert: _, key: _] =
             ClientCertificate.load!(
               ConnectionString.parse(
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
               )
             )
  end

  @tag :tmp_dir
  test "matches Ed25519 and Ed448 identities and rejects mismatched keys", %{tmp_dir: dir} do
    for curve <- ["ed25519", "ed448"] do
      key = Path.join(dir, "#{curve}.key")
      cert = Path.join(dir, "#{curve}.pem")
      bundle = Path.join(dir, "#{curve}-bundle.pem")
      other_key = Path.join(dir, "#{curve}-other.key")

      openssl([
        "req",
        "-x509",
        "-newkey",
        curve,
        "-nodes",
        "-days",
        "1",
        "-subj",
        "/CN=EdDSA",
        "-keyout",
        key,
        "-out",
        cert
      ])

      openssl(["genpkey", "-algorithm", curve, "-out", other_key])
      File.write!(bundle, File.read!(cert) <> File.read!(key))

      assert [cert: _, key: _] =
               ClientCertificate.load!(
                 ConnectionString.parse(
                   "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
                 )
               )

      File.write!(bundle, File.read!(cert) <> File.read!(other_key))

      assert_raise ArgumentError, ~r/invalid client certificate/, fn ->
        ClientCertificate.load!(
          ConnectionString.parse(
            "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
          )
        )
      end
    end
  end

  @tag :tmp_dir
  test "matches a DSA private key to its certificate", %{tmp_dir: dir} do
    params = Path.join(dir, "dsa-params.pem")
    key = Path.join(dir, "dsa.key")
    cert = Path.join(dir, "dsa.pem")
    bundle = Path.join(dir, "dsa-bundle.pem")

    openssl([
      "genpkey",
      "-genparam",
      "-algorithm",
      "DSA",
      "-pkeyopt",
      "dsa_paramgen_bits:1024",
      "-out",
      params
    ])

    openssl(["genpkey", "-paramfile", params, "-out", key])

    openssl([
      "req",
      "-x509",
      "-key",
      key,
      "-sha1",
      "-days",
      "1",
      "-subj",
      "/CN=DSA Client",
      "-out",
      cert
    ])

    File.write!(bundle, File.read!(cert) <> File.read!(key))

    assert [cert: _, key: _] =
             ClientCertificate.load!(
               ConnectionString.parse(
                 "chronicle://localhost?certificatePath=#{URI.encode_www_form(bundle)}"
               )
             )
  end

  defp assert_no_identity_handshake(fixtures, adapter_opts, succeeds?) do
    parent = self()

    {:ok, listener} =
      :ssl.listen(0,
        certfile: fixtures.server_cert,
        keyfile: fixtures.server_key,
        verify: :verify_none,
        alpn_preferred_protocols: ["h2"],
        active: false,
        reuseaddr: true
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)
        result = :ssl.handshake(socket, 5_000)
        if match?({:ok, _}, result), do: :ssl.close(elem(result, 1))
        :ssl.close(listener)
        result
      end)

    [{:Certificate, root, _}] = :public_key.pem_decode(File.read!(fixtures.root_cert))

    {:ok, connection} =
      Connection.start_link(
        connection_string: "chronicle://localhost:#{port}?skipTlsValidation=false",
        grpc_options: [
          adapter_opts: adapter_opts,
          cred: GRPC.Credential.new(ssl: [verify: :verify_peer, cacerts: [root]])
        ],
        connect_fun: fn _target, options ->
          send(parent, {:no_identity_options, options})
          {:ok, %{}}
        end
      )

    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:no_identity_options, options}
    Connection.disconnect(connection)

    channel = %GRPC.Channel{host: "localhost", port: port, scheme: "https", cred: options[:cred]}
    result = GRPC.Client.Adapters.Mint.connect(channel, adapter_opts)
    if match?({:ok, _}, result), do: GRPC.Client.Adapters.Mint.disconnect(elem(result, 1))

    if succeeds? do
      assert {:ok, _} = Task.await(server, 6_000)
    else
      assert {:error, _} = result
      assert {:error, _} = Task.await(server, 6_000)
    end
  end

  defp sign_server_with_intermediate(dir, fixtures) do
    leaf = Path.join(dir, "intermediate-server.pem")

    openssl([
      "x509",
      "-req",
      "-in",
      fixtures.server_csr,
      "-CA",
      fixtures.intermediate_cert,
      "-CAkey",
      fixtures.intermediate_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      fixtures.server_ext,
      "-out",
      leaf
    ])

    leaf
  end

  defp assert_ca_handshake(_dir, fixtures, identity_path, server_chain, trust) do
    parent = self()

    {:ok, connection} =
      Connection.start_link(
        connection_string:
          "chronicle://localhost?certificatePath=#{URI.encode_www_form(identity_path)}&skipTlsValidation=false",
        grpc_options: [cred: GRPC.Credential.new(ssl: trust)],
        connect_fun: fn _target, options ->
          send(parent, {:configured_ssl, options[:cred].ssl})
          {:ok, %{}}
        end,
        disconnect_fun: fn _ -> :ok end
      )

    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:configured_ssl, ssl}
    Connection.disconnect(connection)

    {:ok, listener} =
      :ssl.listen(0,
        certfile: server_chain,
        keyfile: fixtures.server_key,
        verify: :verify_none,
        active: false,
        reuseaddr: true
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)
        result = :ssl.handshake(socket, 5_000)
        if match?({:ok, _}, result), do: :ssl.close(elem(result, 1))
        :ssl.close(listener)
        result
      end)

    assert {:ok, tls} = :ssl.connect(~c"localhost", port, [active: false] ++ ssl, 5_000)
    :ssl.close(tls)
    assert {:ok, _} = Task.await(server, 6_000)
  end

  defp assert_handshake(path, fixtures) do
    cs =
      ConnectionString.parse("chronicle://localhost?certificatePath=#{URI.encode_www_form(path)}")

    identity = ClientCertificate.load!(cs)
    assert is_list(identity[:cert])
    assert length(identity[:cert]) == 2
    assert Auth.transport_opts(false, true, identity)[:transport_opts][:cert] == identity[:cert]

    parent = self()

    {:ok, connection} =
      Connection.start_link(
        connection_string: cs,
        connect_fun: fn _target, options ->
          send(parent, {:grpc_ssl, options[:cred].ssl})
          {:ok, %{}}
        end,
        auto_connect: true
      )

    assert :ok = Connection.connect(connection, 2_000)
    assert_receive {:grpc_ssl, grpc_ssl}
    assert grpc_ssl[:cert] == identity[:cert]
    Connection.disconnect(connection)

    {:ok, listener} =
      :ssl.listen(0,
        certfile: fixtures.server_cert,
        keyfile: fixtures.server_key,
        cacertfile: fixtures.root_cert,
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        active: false,
        reuseaddr: true
      )

    {:ok, {_address, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)

        result =
          with {:ok, tls} <- :ssl.handshake(socket, 5_000),
               {:ok, peer} <- :ssl.peercert(tls) do
            :ssl.close(tls)
            {:ok, peer}
          end

        :ssl.close(listener)
        result
      end)

    {:ok, client} =
      :ssl.connect(~c"localhost", port, [verify: :verify_none, active: false] ++ grpc_ssl, 5_000)

    :ssl.close(client)
    assert {:ok, peer} = Task.await(server, 6_000)
    assert peer == hd(identity[:cert])
  end

  defp chain_fixture(dir) do
    root_cert = Path.join(dir, "root.pem")
    root_key = Path.join(dir, "root.key")

    openssl([
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-days",
      "1",
      "-subj",
      "/CN=Test Root",
      "-addext",
      "basicConstraints=critical,CA:TRUE",
      "-keyout",
      root_key,
      "-out",
      root_cert
    ])

    intermediate_cert = Path.join(dir, "intermediate.pem")
    intermediate_key = Path.join(dir, "intermediate.key")
    intermediate_csr = Path.join(dir, "intermediate.csr")
    intermediate_ext = Path.join(dir, "intermediate.ext")

    File.write!(
      intermediate_ext,
      "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n"
    )

    openssl([
      "req",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-subj",
      "/CN=Test Intermediate",
      "-keyout",
      intermediate_key,
      "-out",
      intermediate_csr
    ])

    openssl([
      "x509",
      "-req",
      "-in",
      intermediate_csr,
      "-CA",
      root_cert,
      "-CAkey",
      root_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      intermediate_ext,
      "-out",
      intermediate_cert
    ])

    client_cert = Path.join(dir, "client.pem")
    client_key = Path.join(dir, "client.key")
    client_csr = Path.join(dir, "client.csr")
    client_ext = Path.join(dir, "client.ext")

    File.write!(
      client_ext,
      "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n"
    )

    openssl([
      "req",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-subj",
      "/CN=Test Client",
      "-keyout",
      client_key,
      "-out",
      client_csr
    ])

    openssl([
      "x509",
      "-req",
      "-in",
      client_csr,
      "-CA",
      intermediate_cert,
      "-CAkey",
      intermediate_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      client_ext,
      "-out",
      client_cert
    ])

    server_cert = Path.join(dir, "server.pem")
    server_key = Path.join(dir, "server.key")
    server_csr = Path.join(dir, "server.csr")
    server_ext = Path.join(dir, "server.ext")

    File.write!(
      server_ext,
      "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n"
    )

    openssl([
      "req",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-subj",
      "/CN=localhost",
      "-keyout",
      server_key,
      "-out",
      server_csr
    ])

    openssl([
      "x509",
      "-req",
      "-in",
      server_csr,
      "-CA",
      root_cert,
      "-CAkey",
      root_key,
      "-CAcreateserial",
      "-days",
      "1",
      "-extfile",
      server_ext,
      "-out",
      server_cert
    ])

    %{
      root_cert: root_cert,
      root_key: root_key,
      intermediate_cert: intermediate_cert,
      intermediate_key: intermediate_key,
      client_cert: client_cert,
      client_key: client_key,
      server_cert: server_cert,
      server_key: server_key,
      server_csr: server_csr,
      server_ext: server_ext
    }
  end

  defp openssl(args) do
    {output, status} = System.cmd("openssl", args, stderr_to_stdout: true)
    assert status == 0, output
  end
end
