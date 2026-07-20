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
    * `:retry_attempts` — maximum reconnect attempts before giving up (default: 5).
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

  require Logger

  alias Chronicle.Connections.{ConnectionString, DnsResolver, LoadBalancer}
  alias Chronicle.Connections.ConnectionString.ServerAddress

  @default_connect_timeout 10_000
  @default_retry_attempts 5
  @default_reconnect_base_delay 1_000
  @default_reconnect_max_delay 10_000

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
    state = %{
      connection_string: connection_string_from(options),
      channel: nil,
      connected?: false,
      connect_fun: Keyword.get(options, :connect_fun, &default_connect/2),
      disconnect_fun: Keyword.get(options, :disconnect_fun, &default_disconnect/1),
      resolve_fun: Keyword.get(options, :resolve_fun, &DnsResolver.resolve/2),
      probe_fun: Keyword.get(options, :probe_fun, &LoadBalancer.default_probe/3),
      grpc_options: Keyword.get(options, :grpc_options, []),
      retry_attempts: Keyword.get(options, :retry_attempts, @default_retry_attempts),
      reconnect_base_delay:
        Keyword.get(options, :reconnect_base_delay, @default_reconnect_base_delay),
      reconnect_max_delay:
        Keyword.get(options, :reconnect_max_delay, @default_reconnect_max_delay),
      reconnect_attempt: 0,
      reconnect_timer: nil,
      connection_process: nil,
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

  def handle_call(:disconnect, _from, state) do
    state = disconnect_channel(state)
    state = fail_pending_connects(state, {:error, :disconnected})
    {:stop, :normal, :ok, %{state | connected?: false, channel: nil, connection_process: nil}}
  end

  @impl true
  def handle_info(:connect, %{connected?: true} = state) do
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    state = %{state | reconnect_timer: nil}
    spawn_connect_attempt(state)
    {:noreply, %{state | round_robin_counter: state.round_robin_counter + 1}}
  end

  def handle_info({:connect_result, {:ok, channel}}, state) do
    {:noreply, succeed_connect(state, channel)}
  end

  def handle_info({:connect_result, {:error, _reason}}, state) do
    {:noreply,
     schedule_reconnect(%{state | channel: nil, connected?: false, connection_process: nil})}
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

    Task.start(fn ->
      result =
        with {:ok, addresses} <- resolve_addresses(connection_string, resolve_fun),
             {:ok, address} <-
               LoadBalancer.select(addresses, connection_string, round_robin_counter, probe_fun) do
          target = target_for(address)
          opts = build_grpc_options(connection_string, grpc_options)
          connect_fun.(target, opts)
        end

      send(parent, {:connect_result, result})
    end)
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
      reconnect_attempt: 0,
      reconnect_timer: nil,
      connection_process: connection_process
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

  defp disconnect_channel(%{channel: nil} = state), do: state

  defp disconnect_channel(%{channel: channel, disconnect_fun: disconnect_fun} = state) do
    cancel_timer(state.reconnect_timer)

    try do
      disconnect_fun.(channel)
    rescue
      _error -> :ok
    end

    %{state | reconnect_timer: nil}
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

  defp build_grpc_options(connection_string, grpc_options) do
    headers = auth_headers(connection_string)

    options =
      [
        adapter: GRPC.Client.Adapters.Mint,
        headers: headers
      ]
      |> Keyword.merge(grpc_options)

    cond do
      connection_string.disable_tls or not Code.ensure_loaded?(GRPC.Credential) ->
        options

      connection_string.skip_tls_validation ->
        # Default: trust any certificate without validating its chain, since a
        # Chronicle kernel commonly serves an auto-generated self-signed
        # certificate. Set `skipTlsValidation=false` (or the
        # `:skip_tls_validation` option) to require full chain validation
        # instead, against a server whose certificate is verifiable.
        credential = apply(GRPC.Credential, :new, [[ssl: [verify: :verify_none]]])
        Keyword.put_new(options, :cred, credential)

      true ->
        # Explicit opt-in: validate the server's certificate chain against the
        # system trust store.
        credential =
          apply(GRPC.Credential, :new, [
            [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]]
          ])

        Keyword.put_new(options, :cred, credential)
    end
  end

  defp auth_headers(connection_string) do
    cond do
      present?(connection_string.api_key) ->
        [{"api-key", connection_string.api_key}]

      present?(connection_string.username) and present?(connection_string.password) ->
        cs = connection_string
        address = ConnectionString.server_address(cs)

        # Chronicle serves OAuth on the same port as the gRPC connection, on
        # the first configured host. Use explicit auth_port only when the
        # caller configured a distinct OAuth authority.
        port = cs.auth_port || address.port

        case Chronicle.Connections.Auth.fetch_token(
               address.host,
               port,
               cs.username,
               cs.password,
               cs.disable_tls,
               cs.skip_tls_validation
             ) do
          {:ok, token} ->
            [{"authorization", "Bearer #{token}"}]

          {:error, reason} ->
            Logger.warning("Failed to fetch OAuth2 token: #{inspect(reason)}")
            []
        end

      true ->
        []
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp connection_process_for(%{adapter_payload: %{conn_pid: pid}}) when is_pid(pid), do: pid
  defp connection_process_for(_channel), do: nil

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer_ref), do: Process.cancel_timer(timer_ref)

  defp call_timeout(:infinity), do: :infinity
  defp call_timeout(timeout) when is_integer(timeout), do: timeout + 100

  defp default_connect(target, options), do: apply(GRPC.Stub, :connect, [target, options])
  defp default_disconnect(channel), do: apply(GRPC.Stub, :disconnect, [channel])
end
