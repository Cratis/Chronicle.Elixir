# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Connection do
  @moduledoc """
  Manages a resilient Chronicle gRPC channel with automatic reconnection.

  `Connection` is a `GenServer` that maintains a gRPC channel to a Chronicle
  kernel. It handles connection failures with exponential backoff and notifies
  callers waiting for the connection to become ready.

  ## Usage

  Start it as part of your supervision tree, typically via `Chronicle.Client`:

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000?disableTls=true",
        ...}

  Or start it directly for lower-level use:

      {:ok, conn} = Chronicle.Connections.Connection.start_link(
        connection_string: "chronicle://localhost:35000?disableTls=true",
        name: :my_conn
      )
      :ok = Chronicle.Connections.Connection.connect(:my_conn)
      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)

  ## Options

    * `:connection_string` — a `Chronicle.Connections.ConnectionString` struct or
      a connection string binary. Defaults to `ConnectionString.default/0`.
    * `:server_address` — alternative to `:connection_string`; a `"host:port"` string.
    * `:grpc_options` — additional options passed to `GRPC.Stub.connect/2`.
    * `:retry_attempts` — maximum reconnect attempts before giving up (default: 5).
    * `:reconnect_base_delay` — base reconnect delay in milliseconds (default: 1000).
    * `:reconnect_max_delay` — maximum reconnect delay in milliseconds (default: 10000).
    * `:auto_connect` — whether to connect immediately on start (default: `true`).
    * `:name` — registered name for the GenServer process.
  """

  use GenServer

  require Logger

  alias Chronicle.Connections.ConnectionString

  @default_connect_timeout 10_000
  @default_retry_attempts 5
  @default_reconnect_base_delay 1_000
  @default_reconnect_max_delay 10_000

  @type option ::
          {:connection_string, String.t() | ConnectionString.t()}
          | {:server_address, String.t()}
          | {:grpc_options, keyword()}
          | {:retry_attempts, non_neg_integer()}
          | {:reconnect_base_delay, non_neg_integer()}
          | {:reconnect_max_delay, non_neg_integer()}
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
      grpc_options: Keyword.get(options, :grpc_options, []),
      retry_attempts: Keyword.get(options, :retry_attempts, @default_retry_attempts),
      reconnect_base_delay:
        Keyword.get(options, :reconnect_base_delay, @default_reconnect_base_delay),
      reconnect_max_delay:
        Keyword.get(options, :reconnect_max_delay, @default_reconnect_max_delay),
      reconnect_attempt: 0,
      reconnect_timer: nil,
      connection_process: nil,
      pending_connects: []
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
    {:noreply, state}
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
    target = target_for(state.connection_string)
    connection_string = state.connection_string
    grpc_options = state.grpc_options
    connect_fun = state.connect_fun

    Task.start(fn ->
      opts = build_grpc_options(connection_string, grpc_options)
      result = connect_fun.(target, opts)
      send(parent, {:connect_result, result})
    end)
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

  defp target_for(connection_string) do
    "#{connection_string.server_address.host}:#{connection_string.server_address.port}"
  end

  defp build_grpc_options(connection_string, grpc_options) do
    headers = auth_headers(connection_string)

    options =
      [
        adapter: GRPC.Client.Adapters.Mint,
        headers: headers
      ]
      |> Keyword.merge(grpc_options)

    if connection_string.disable_tls or not Code.ensure_loaded?(GRPC.Credential) do
      options
    else
      credential = apply(GRPC.Credential, :new, [[ssl: []]])
      Keyword.put_new(options, :cred, credential)
    end
  end

  defp auth_headers(connection_string) do
    cond do
      present?(connection_string.api_key) ->
        [{"api-key", connection_string.api_key}]

      present?(connection_string.username) and present?(connection_string.password) ->
        cs = connection_string
        host = cs.server_address.host

        # Use explicit auth_port if provided, otherwise default to 8080 (Chronicle's management port)
        port = cs.auth_port || 8080

        case Chronicle.Connections.Auth.fetch_token(
               host,
               port,
               cs.username,
               cs.password,
               cs.disable_tls
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
