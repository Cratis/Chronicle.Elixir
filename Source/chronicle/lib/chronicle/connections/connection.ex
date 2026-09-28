# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Connection do
  @moduledoc """
  Manages a resilient Chronicle gRPC channel with automatic reconnection.

  `Connection` is a `GenServer` that maintains a gRPC channel to a Chronicle
  kernel. It handles connection failures with exponential backoff and notifies
  callers waiting for the connection to become ready.

  On every connect/reconnect attempt it re-resolves the connection string's
  addresses — a static multi-host list, or a fresh DNS SRV lookup for
  `chronicle+srv://` (see `Chronicle.Connections.DnsResolver`) — and picks one
  via the configured load-balancer strategy (see `Chronicle.Connections.LoadBalancer`)
  before dialing. Re-resolving on every attempt means a `chronicle+srv://`
  record change, or a host coming back up, is picked up automatically without
  a separate background refresh loop.

  ## Usage

  Start it as part of your supervision tree, typically via `Chronicle.Client`:

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        ...}

  Or start it directly for lower-level use:

      {:ok, conn} = Chronicle.Connections.Connection.start_link(
        connection_string: "chronicle://localhost:35000",
        name: :my_conn
      )
      :ok = Chronicle.Connections.Connection.connect(:my_conn)
      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)

  ## Options

    * `:connection_string` — a `Chronicle.Connections.ConnectionString` struct or
      a connection string binary. Defaults to `ConnectionString.default/0`.
    * `:server_address` — alternative to `:connection_string`; a `"host:port"` string.
    * `:skip_tls_validation` — overrides the connection string's `skipTlsValidation`
      query option. When `true`, the gRPC channel and the OAuth2 token fetch skip TLS
      certificate chain validation instead of validating against the system trust store.
    * `:load_balancer` — overrides the connection string's `loadBalancer` query
      option (`:least_connections`, `:round_robin`, or `:random`).
    * `:grpc_options` — additional options passed to `GRPC.Stub.connect/2`.
    * `:retry_attempts` — accepted for backward compatibility and ignored. The
      connection keeps reconnecting, with backoff, for as long as it runs.
    * `:reconnect_base_delay` — base reconnect delay in milliseconds (default: 1000).
    * `:reconnect_max_delay` — maximum reconnect delay in milliseconds (default: 10000).
    * `:auto_connect` — whether to connect immediately on start (default: `true`).
    * `:resolve_fun` — resolves a `chronicle+srv://` host to candidate addresses.
      Defaults to `Chronicle.Connections.DnsResolver.resolve/2`. Test-only seam,
      mirroring `:connect_fun`/`:disconnect_fun` below.
    * `:probe_fun` — performs the `:least_connections` HTTP probe. Defaults to
      `Chronicle.Connections.LoadBalancer.default_probe/3`. Test-only seam.
    * `:connect_fun` — test-only seam replacing `GRPC.Stub.connect/2`.
    * `:disconnect_fun` — test-only seam replacing `GRPC.Stub.disconnect/1`.
    * `:name` — registered name for the GenServer process.
  """

  use GenServer

  alias Chronicle.Connections.{
    AppendCompatibility,
    AuthInterceptor,
    ClientCertificate,
    TransportFailureInterceptor,
    ConnectionString,
    DnsResolver,
    LoadBalancer,
    Status,
    TokenProvider
  }

  alias Chronicle.Connections.ConnectionString.ServerAddress

  @default_connect_timeout 10_000
  @default_retry_attempts 5
  @default_reconnect_base_delay 1_000
  @default_reconnect_max_delay 10_000
  # grpc 1.0.5 replaces (rather than merges) its Mint client_settings when supplied.
  @mint_client_settings [
    initial_window_size: 8_000_000,
    max_frame_size: 8_000_000,
    enable_push: false
  ]

  @type option ::
          {:connection_string, String.t() | ConnectionString.t()}
          | {:server_address, String.t()}
          | {:skip_tls_validation, boolean()}
          | {:load_balancer, ConnectionString.load_balancer_strategy()}
          | {:grpc_options, keyword()}
          | {:retry_attempts, non_neg_integer()}
          | {:reconnect_base_delay, non_neg_integer()}
          | {:reconnect_max_delay, non_neg_integer()}
          | {:resolve_fun,
             (String.t(), String.t() | nil -> {:ok, [ServerAddress.t()]} | {:error, term()})}
          | {:probe_fun, LoadBalancer.probe_fun()}
          | {:connect_fun, (String.t(), keyword() -> {:ok, term()} | {:error, term()})}
          | {:disconnect_fun, (term() -> any())}
          | {:name, GenServer.name()}
          | {:auto_connect, boolean()}

  @doc """
  Starts a Chronicle connection process linked to the current process.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  @doc """
  Waits until the connection is ready, or returns `{:error, :timeout}`.

  Blocks the caller until the gRPC channel is established or `timeout`
  milliseconds elapse.
  """
  @spec connect(GenServer.server(), timeout()) :: :ok | {:error, :timeout}
  def connect(connection, timeout \\ @default_connect_timeout) do
    GenServer.call(connection, {:await_connected, timeout}, call_timeout(timeout))
  end

  @doc """
  Returns `true` if the channel is currently connected.
  """
  @spec connected?(GenServer.server()) :: boolean()
  def connected?(connection) do
    GenServer.call(connection, :connected?)
  end

  @doc """
  Returns `{:ok, channel}` when connected, or `{:error, :not_connected}`.
  """
  @spec channel(GenServer.server()) :: {:ok, term()} | {:error, :not_connected}
  def channel(connection) do
    GenServer.call(connection, :channel)
  end

  @doc false
  @spec append_channel(GenServer.server()) :: {:ok, term()} | {:error, term()}
  def append_channel(connection) do
    GenServer.call(connection, :append_channel, :infinity)
  end

  @doc """
  Drops the current channel and dials a fresh one.

  For callers with independent evidence that the channel is unusable — such as
  the session watchdog detecting missed keepalives. A channel can die in ways
  this process cannot observe: the gRPC adapter reports transport death to the
  process that dialed (a completed connect task, not this server), and an
  expired auth token fails every new RPC while the transport stays healthy.
  Redialing re-resolves addresses and re-fetches authentication headers.
  No-op while a connect attempt is already in progress.
  """
  @spec reconnect(GenServer.server()) :: :ok
  def reconnect(connection) do
    GenServer.cast(connection, :reconnect)
  end

  @doc """
  Disconnects the active channel and stops reconnect attempts.

  The process exits normally after this call.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(connection) do
    GenServer.call(connection, :disconnect)
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    connection_string = connection_string_from(options)
    client_certificate = ClientCertificate.load!(connection_string)
    grpc_options = Keyword.get(options, :grpc_options, [])
    validate_certificate_options!(grpc_options, client_certificate)
    validate_push_options!(grpc_options)

    state = %{
      connection_string: connection_string,
      client_certificate: client_certificate,
      token_provider: start_token_provider(connection_string, client_certificate),
      channel: nil,
      connected?: false,
      append_compatible?: false,
      connect_fun: Keyword.get(options, :connect_fun, &default_connect/2),
      disconnect_fun: Keyword.get(options, :disconnect_fun, &default_disconnect/1),
      resolve_fun: Keyword.get(options, :resolve_fun, &DnsResolver.resolve/2),
      probe_fun: Keyword.get(options, :probe_fun, &LoadBalancer.default_probe/3),
      grpc_options: grpc_options,
      retry_attempts: Keyword.get(options, :retry_attempts, @default_retry_attempts),
      reconnect_base_delay:
        Keyword.get(options, :reconnect_base_delay, @default_reconnect_base_delay),
      reconnect_max_delay:
        Keyword.get(options, :reconnect_max_delay, @default_reconnect_max_delay),
      reconnect_attempt: 0,
      reconnect_timer: nil,
      connection_process: nil,
      connection_monitor: nil,
      connect_attempt: nil,
      pending_connects: [],
      # Round-robin's counter starts at a random offset (not 0) so a fleet of
      # clients reconnecting together doesn't all dial the same first host;
      # it belongs here, in the one `Connection` process it is scoped to,
      # rather than in `LoadBalancer` (which holds no state of its own).
      round_robin_counter: :rand.uniform(1_000_000_000)
    }

    if Keyword.get(options, :auto_connect, true) do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def format_status(%{state: state} = status) do
    Status.redact(status,
      connection_string: :redacted,
      client_certificate: :redacted,
      grpc_options: :redacted,
      channel: if(state.channel, do: :connected, else: nil)
    )
  end

  @impl true
  def handle_call({:await_connected, _timeout}, _from, %{connected?: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:await_connected, timeout}, from, state) do
    timer_ref =
      if timeout == :infinity do
        nil
      else
        Process.send_after(self(), {:connect_timeout, from}, timeout)
      end

    {:noreply, %{state | pending_connects: [{from, timer_ref} | state.pending_connects]}}
  end

  def handle_call(:connected?, _from, state) do
    {:reply, state.connected?, state}
  end

  def handle_call(:channel, _from, %{channel: channel, connected?: true} = state) do
    {:reply, {:ok, channel}, state}
  end

  def handle_call(:channel, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:append_channel, _from, %{connected?: true} = state) do
    # Serialize the first check per channel across callers. Only success is
    # retained: an unavailable compatibility endpoint must be retried, not cached.
    case if(state.append_compatible?, do: :ok, else: AppendCompatibility.check(state.channel)) do
      :ok -> {:reply, {:ok, state.channel}, %{state | append_compatible?: true}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:append_channel, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:disconnect, _from, state) do
    state = disconnect_channel(state)
    state = fail_pending_connects(state, {:error, :disconnected})
    # The provider is linked, but a :normal stop does not propagate over the
    # link — stop it explicitly so it does not outlive the connection.
    stop_token_provider(state.token_provider)
    {:stop, :normal, :ok, %{state | connected?: false, channel: nil, connection_process: nil}}
  end

  # A missing clause would put the entire state (and the caller arguments) in
  # the stacktrace. OTP's GenServer crash reporter appends that stacktrace
  # outside format_status/1, so redact :reason AND avoid argument-bearing frames.
  def handle_call(_request, _from, _state) do
    raise FunctionClauseError, module: __MODULE__, function: :handle_call, arity: 3
  end

  @impl true
  def terminate(_reason, state) do
    disconnect_channel(state)
    stop_token_provider(state.token_provider)
    :ok
  end

  @impl true
  def handle_cast(:reconnect, %{connected?: false} = state) do
    # Not connected: a dial or backoff cycle already owns recovery.
    {:noreply, state}
  end

  def handle_cast(:reconnect, state) do
    state =
      state
      |> disconnect_channel()
      |> Map.merge(%{connected?: false, channel: nil, connection_process: nil})

    # Dial immediately rather than through the backoff: the caller has already
    # waited out its own retry delay before asking for a fresh channel.
    send(self(), :connect)
    {:noreply, state}
  end

  # A missing clause prints the live channel (and API-key headers) in the
  # callback stack frame even though format_status/1 redacts the state.
  def handle_cast(_message, _state) do
    raise FunctionClauseError, module: __MODULE__, function: :handle_cast, arity: 2
  end

  @impl true
  def handle_info(:connect, %{connected?: true} = state) do
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    state = %{state | reconnect_timer: nil}
    attempt = spawn_connect_attempt(state)

    {:noreply,
     %{state | connect_attempt: attempt, round_robin_counter: state.round_robin_counter + 1}}
  end

  def handle_info(
        {:connect_result, attempt, {:ok, channel}},
        %{connect_attempt: attempt} = state
      ) do
    state = succeed_connect(state, channel)
    send(attempt, {:connect_accepted, self()})
    {:noreply, %{state | connect_attempt: nil}}
  end

  def handle_info(
        {:connect_result, attempt, {:error, _reason}},
        %{connect_attempt: attempt} = state
      ) do
    {:noreply,
     schedule_reconnect(%{
       state
       | connect_attempt: nil,
         channel: nil,
         connected?: false,
         connection_process: nil
     })}
  end

  def handle_info({:connect_result, _attempt, {:ok, channel}}, state) do
    disconnect_orphan(channel, state.disconnect_fun)
    {:noreply, state}
  end

  def handle_info({:connect_timeout, from}, state) do
    {matches, remaining} =
      Enum.split_with(state.pending_connects, fn {pending_from, _} -> pending_from == from end)

    Enum.each(matches, fn {pending_from, _} ->
      GenServer.reply(pending_from, {:error, :timeout})
    end)

    {:noreply, %{state | pending_connects: remaining}}
  end

  def handle_info({:elixir_grpc, :connection_down, pid}, state)
      when pid == state.connection_process do
    {:noreply, handle_connection_down(state)}
  end

  def handle_info({:gun_down, pid, _protocol, _reason}, state)
      when pid == state.connection_process do
    {:noreply, handle_connection_down(state)}
  end

  def handle_info({:gun_down, pid, _protocol, _reason, _streams}, state)
      when pid == state.connection_process do
    {:noreply, handle_connection_down(state)}
  end

  # The adapter's connection process crashing outright (as opposed to reporting
  # transport death) is only visible through the monitor placed on it when the
  # channel came up.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{connection_monitor: ref} = state) do
    {:noreply, handle_connection_down(state)}
  end

  # Trapping exits for shutdown cleanup must not turn linked provider or signer
  # crashes into ignored messages. The signer monitors us to release its key.
  def handle_info({:EXIT, provider, reason}, %{token_provider: provider} = state)
      when is_pid(provider) do
    {:stop, reason, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp spawn_connect_attempt(state) do
    parent = self()
    connection_string = state.connection_string
    grpc_options = state.grpc_options
    connect_fun = state.connect_fun
    resolve_fun = state.resolve_fun
    probe_fun = state.probe_fun
    round_robin_counter = state.round_robin_counter
    token_provider = state.token_provider
    client_certificate = state.client_certificate
    disconnect_fun = state.disconnect_fun

    {:ok, attempt} =
      Task.start(fn ->
        owner_monitor = Process.monitor(parent)

        result =
          with {:ok, addresses} <- resolve_addresses(connection_string, resolve_fun),
               {:ok, address} <-
                 LoadBalancer.select(addresses, connection_string, round_robin_counter, probe_fun) do
            target = target_for(address)

            opts =
              build_grpc_options(
                connection_string,
                grpc_options,
                token_provider,
                client_certificate
              )

            connect_fun.(target, opts)
          end

        send(parent, {:connect_result, self(), result})

        if match?({:ok, _}, result) do
          receive do
            {:connect_accepted, ^parent} ->
              :ok

            {:DOWN, ^owner_monitor, :process, ^parent, _reason} ->
              {:ok, channel} = result
              disconnect_orphan(channel, disconnect_fun)
          end
        end
      end)

    attempt
  end

  # Resolves the connection string's candidate addresses. `chronicle+srv://`
  # holds a single unresolved host and is resolved fresh via `resolve_fun` on
  # every call (i.e. every connect/reconnect attempt); a plain multi-host
  # `chronicle://` already has its full candidate list from parsing.
  defp resolve_addresses(
         %ConnectionString{scheme: "chronicle+srv"} = connection_string,
         resolve_fun
       ) do
    case ConnectionString.server_address(connection_string) do
      nil -> {:error, :no_addresses}
      %ServerAddress{host: host} -> resolve_fun.(host, connection_string.srv_name_server)
    end
  end

  defp resolve_addresses(%ConnectionString{server_addresses: addresses}, _resolve_fun) do
    {:ok, addresses}
  end

  defp succeed_connect(state, channel) do
    connection_process = connection_process_for(channel)

    state
    |> disconnect_channel()
    |> Map.merge(%{
      channel: channel,
      connected?: true,
      append_compatible?: false,
      reconnect_attempt: 0,
      reconnect_timer: nil,
      connection_process: connection_process,
      connection_monitor: monitor_connection_process(connection_process)
    })
    |> reply_pending_connects(:ok)
  end

  defp handle_connection_down(state) do
    state
    |> disconnect_channel()
    |> Map.merge(%{connected?: false, channel: nil, connection_process: nil})
    |> schedule_reconnect()
  end

  defp schedule_reconnect(%{reconnect_timer: timer_ref} = state) when not is_nil(timer_ref),
    do: state

  defp schedule_reconnect(state) do
    delay =
      state.reconnect_base_delay
      |> Kernel.*(Integer.pow(2, state.reconnect_attempt))
      |> min(state.reconnect_max_delay)

    timer_ref = Process.send_after(self(), :connect, delay)

    %{state | reconnect_timer: timer_ref, reconnect_attempt: state.reconnect_attempt + 1}
  end

  defp reply_pending_connects(state, reply) do
    Enum.each(state.pending_connects, fn {from, timer_ref} ->
      cancel_timer(timer_ref)
      GenServer.reply(from, reply)
    end)

    %{state | pending_connects: []}
  end

  defp fail_pending_connects(state, reply), do: reply_pending_connects(state, reply)

  defp disconnect_orphan(channel, disconnect_fun) do
    disconnect_fun.(channel)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp disconnect_channel(%{channel: nil} = state), do: state

  defp disconnect_channel(%{channel: channel, disconnect_fun: disconnect_fun} = state) do
    cancel_timer(state.reconnect_timer)
    demonitor(state.connection_monitor)

    try do
      disconnect_fun.(channel)
    rescue
      _error -> :ok
    end

    %{state | reconnect_timer: nil, connection_monitor: nil}
  end

  defp connection_string_from(options) do
    options
    |> base_connection_string()
    |> apply_option_override(options, :skip_tls_validation)
    |> apply_option_override(options, :load_balancer)
  end

  defp base_connection_string(options) do
    cond do
      match?(%ConnectionString{}, options[:connection_string]) ->
        options[:connection_string]

      is_binary(options[:connection_string]) ->
        ConnectionString.parse(options[:connection_string])

      is_binary(options[:server_address]) ->
        ConnectionString.parse("chronicle://#{options[:server_address]}")

      true ->
        ConnectionString.default()
    end
  end

  # `:skip_tls_validation`/`:load_balancer` can be set directly as `Connection`
  # (or `Chronicle.Client`) options, overriding whatever the connection string
  # itself specifies — useful when the connection string comes from elsewhere
  # (e.g. a discovered `chronicle+srv://` host) but the caller still wants to
  # pin the load-balancer strategy or TLS validation behavior explicitly.
  defp apply_option_override(connection_string, options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> Map.put(connection_string, key, value)
      :error -> connection_string
    end
  end

  # Builds the gRPC target for a single, already-selected address. Uses the
  # explicit `ipv4:`/`ipv6:` schemes (rather than a bare "host:port") because
  # the underlying grpc-elixir dependency's default resolver only special-cases
  # the literal host "localhost" for bare host:port strings — any other real
  # hostname would fail resolution outright. `ipv4:` here doesn't mean the host
  # must be an IPv4 literal: the resolver passes the address straight through
  # to the transport adapter, which resolves hostnames itself.
  defp target_for(%ServerAddress{host: host, port: port}) do
    if String.contains?(host, ":") do
      "ipv6:[#{host}]:#{port}"
    else
      "ipv4:#{host}:#{port}"
    end
  end

  defp build_grpc_options(connection_string, grpc_options, token_provider, client_certificate) do
    headers = auth_headers(connection_string)

    options =
      [
        adapter: GRPC.Client.Adapters.Mint,
        headers: headers
      ]
      |> Keyword.merge(grpc_options)
      |> disable_server_push()
      |> add_auth_interceptor(token_provider)
      |> add_transport_failure_interceptor()

    cond do
      connection_string.disable_tls ->
        options

      connection_string.skip_tls_validation ->
        # Chronicle commonly serves an auto-generated self-signed certificate.
        add_credential(options, [verify: :verify_none], client_certificate)

      true ->
        add_credential(
          options,
          [verify: :verify_peer, cacerts: :public_key.cacerts_get()],
          client_certificate
        )
    end
  end

  defp disable_server_push(options) do
    if options[:adapter] == GRPC.Client.Adapters.Mint do
      adapter_opts = Keyword.get(options, :adapter_opts, [])
      client_settings = force_push_off(Keyword.get(adapter_opts, :client_settings, []))

      adapter_opts =
        Keyword.update(adapter_opts, :config_options, [client_settings: client_settings], fn
          config_options ->
            Keyword.put(
              config_options,
              :client_settings,
              force_push_off(Keyword.get(config_options, :client_settings, client_settings))
            )
        end)

      Keyword.put(
        options,
        :adapter_opts,
        Keyword.put(adapter_opts, :client_settings, client_settings)
      )
    else
      options
    end
  end

  defp force_push_off(settings) do
    @mint_client_settings
    |> Keyword.merge(settings)
    |> Keyword.put(:enable_push, false)
  end

  # grpc merges application module options after the per-channel settings.
  # Unlike config_options they cannot be rewritten for this one connection.
  defp validate_push_options!(options) do
    if Keyword.get(options, :adapter, GRPC.Client.Adapters.Mint) == GRPC.Client.Adapters.Mint do
      case Application.fetch_env(:grpc, GRPC.Client.Adapters.Mint) do
        {:ok, module_opts} ->
          if Keyword.has_key?(module_opts, :client_settings) and
               Keyword.get(module_opts, :client_settings)[:enable_push] != false do
            raise ArgumentError,
                  "Mint module client_settings must set enable_push: false (gRPC overrides Chronicle's push setting)"
          end

        :error ->
          :ok
      end
    end
  end

  @identity_options [:certs_keys, :cert, :key, :certfile, :keyfile, :password]
  # OTP ssl client_option_cert/common_option_cert, common_option (signatures),
  # and client_option_legacy (verify):
  # https://www.erlang.org/doc/apps/ssl/ssl.html#t:client_option_cert/0
  # https://www.erlang.org/doc/apps/ssl/ssl.html#t:common_option_cert/0
  # https://www.erlang.org/doc/apps/ssl/ssl.html#t:common_option/0
  # https://www.erlang.org/doc/apps/ssl/ssl.html#t:client_option_legacy/0
  @server_verification_options [
    :verify,
    :verify_fun,
    :partial_chain,
    :cacerts,
    :cacertfile,
    :customize_hostname_check,
    :server_name_indication,
    :depth,
    :crl_check,
    :crl_cache,
    :cert_policy_opts,
    :allow_any_ca_purpose,
    :certificate_authorities,
    :stapling,
    :signature_algs,
    :signature_algs_cert
  ]

  defp validate_certificate_options!(_options, []), do: :ok

  defp validate_certificate_options!(options, _certificate) do
    if Keyword.get(options, :adapter, GRPC.Client.Adapters.Mint) != GRPC.Client.Adapters.Mint do
      raise ArgumentError, "client certificates require the Mint gRPC adapter"
    end

    ssl =
      case options[:cred] do
        nil -> []
        %GRPC.Credential{ssl: existing} -> existing
        _ -> raise ArgumentError, "client certificates require a GRPC.Credential"
      end

    adapter_opts = Keyword.get(options, :adapter_opts, [])
    transport_opts = Keyword.get(adapter_opts, :transport_opts, [])
    # grpc 1.0.5 merges module options after the credential's SSL settings;
    # any module transport_opts replaces the entire list, including cert/key.
    module_opts =
      Application.get_env(
        :grpc,
        GRPC.Client.Adapters.Mint,
        Keyword.get(adapter_opts, :config_options, [])
      )

    if Keyword.has_key?(module_opts, :transport_opts) do
      raise ArgumentError,
            "client certificate conflicts with Mint module transport_opts (gRPC overrides the client identity)"
    end

    if Enum.any?(ssl ++ transport_opts, fn {key, _} -> key in @identity_options end) do
      raise ArgumentError, "client certificate conflicts with existing gRPC TLS identity options"
    end

    # grpc 1.0.5 merges credential SSL after adapter transport_opts, so
    # adapter-level verification can be silently overridden by the credential.
    if Enum.any?(transport_opts, fn {key, _} ->
         key in @server_verification_options or
           (is_atom(key) and String.starts_with?(Atom.to_string(key), "ocsp_"))
       end) do
      raise ArgumentError,
            "client certificate conflicts with adapter_opts transport_opts server verification; put verification settings on the GRPC.Credential instead"
    end
  end

  defp add_credential(options, ssl, []) do
    Keyword.put_new(options, :cred, GRPC.Credential.new(ssl: ssl))
  end

  defp add_credential(options, ssl, client_certificate) do
    if options[:adapter] != GRPC.Client.Adapters.Mint do
      raise ArgumentError, "client certificates require the Mint gRPC adapter"
    end

    existing_ssl =
      case options[:cred] do
        nil -> ssl
        %GRPC.Credential{ssl: existing} -> existing
        _ -> raise ArgumentError, "client certificates require a GRPC.Credential"
      end

    credential = GRPC.Credential.new(ssl: Keyword.merge(existing_ssl, client_certificate))
    Keyword.put(options, :cred, credential)
  end

  # The API key is static, so it can live in the channel headers. OAuth2
  # tokens expire and are attached per RPC by the auth interceptor instead —
  # a token baked into the channel would silently invalidate it at expiry.
  defp auth_headers(connection_string) do
    if present?(connection_string.api_key) do
      [{"api-key", connection_string.api_key}]
    else
      []
    end
  end

  # Client credentials mean OAuth2: a linked TokenProvider owns the token
  # lifecycle, and every dialed channel gets an interceptor that attaches a
  # fresh token to each RPC. Mirrors the api-key-wins precedence of
  # `auth_headers/1` when both are (mis)configured.
  defp start_token_provider(connection_string, client_certificate) do
    if present?(connection_string.username) and present?(connection_string.password) and
         not present?(connection_string.api_key) do
      {:ok, provider} =
        TokenProvider.start_link(
          connection_string: connection_string,
          client_certificate: client_certificate
        )

      provider
    end
  end

  defp stop_token_provider(nil), do: :ok

  defp stop_token_provider(provider) do
    if Process.alive?(provider) do
      GenServer.stop(provider)
    end
  catch
    :exit, {:noproc, _} -> :ok
  end

  # Appended, so grpc-elixir runs it outermost around every other interceptor and the transport.
  defp add_transport_failure_interceptor(options) do
    Keyword.update(
      options,
      :interceptors,
      [TransportFailureInterceptor],
      &(&1 ++ [TransportFailureInterceptor])
    )
  end

  # Prepend rather than replace so caller-supplied interceptors survive.
  defp add_auth_interceptor(options, nil), do: options

  defp add_auth_interceptor(options, provider) do
    interceptor = {AuthInterceptor, provider: provider}
    Keyword.update(options, :interceptors, [interceptor], &[interceptor | &1])
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp connection_process_for(%{adapter_payload: %{conn_pid: pid}}) when is_pid(pid), do: pid
  defp connection_process_for(_channel), do: nil

  defp monitor_connection_process(nil), do: nil
  defp monitor_connection_process(pid), do: Process.monitor(pid)

  defp demonitor(nil), do: :ok
  defp demonitor(ref), do: Process.demonitor(ref, [:flush])

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer_ref), do: Process.cancel_timer(timer_ref)

  defp call_timeout(:infinity), do: :infinity
  defp call_timeout(timeout) when is_integer(timeout), do: timeout + 100

  defp default_connect(target, options), do: apply(GRPC.Stub, :connect, [target, options])
  defp default_disconnect(channel), do: apply(GRPC.Stub, :disconnect, [channel])
end
