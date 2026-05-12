# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Session do
  @moduledoc false

  # Establishes and maintains a Chronicle client session via
  # ConnectionService.Connect. Chronicle requires a client to register its
  # ConnectionId before reactors or reducers can register observers.
  #
  # The server registers the client asynchronously in a Task.Run AFTER returning
  # the Connect stream, and only sends the first keepalive AFTER that registration
  # completes (plus ~1 second). So `ready?` is set to true on the first keepalive,
  # and observers (reactors/reducers) must wait until then before registering.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.Clients.{
    ConnectionService,
    ConnectRequest
  }

  @retry_delay 3_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name_for(opts[:client_name]))
  end

  @doc """
  Returns the connection ID for the session registered under `client_name`.
  """
  @spec connection_id(atom()) :: String.t()
  def connection_id(session_name) do
    GenServer.call(session_name, :connection_id)
  end

  @doc """
  Blocks until the session has received the first server keepalive, which means
  the server has finished calling OnClientConnected and the client is registered.
  Returns `:ok`.
  """
  @spec wait_until_ready(atom(), timeout()) :: :ok | {:error, :timeout}
  def wait_until_ready(session_name, timeout \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(session_name, deadline)
  end

  defp do_wait(session_name, deadline) do
    case GenServer.call(session_name, :ready?) do
      true ->
        :ok

      false ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:error, :timeout}
        else
          Process.sleep(min(200, remaining))
          do_wait(session_name, deadline)
        end
    end
  end

  @impl true
  def init(opts) do
    state = %{
      connection: Keyword.fetch!(opts, :connection),
      connection_id: generate_connection_id(),
      keepalive_task: nil,
      ready?: false
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call(:connection_id, _from, state) do
    {:reply, state.connection_id, state}
  end

  def handle_call(:ready?, _from, state) do
    {:reply, state.ready?, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case Connection.channel(state.connection) do
      {:ok, channel} ->
        case start_session(channel, state) do
          {:ok, new_state} ->
            Logger.debug("Chronicle session established: #{new_state.connection_id}")
            {:noreply, new_state}

          {:error, reason} ->
            Logger.warning("Chronicle session failed to start: #{inspect(reason)}, retrying...")
            Process.send_after(self(), :connect, @retry_delay)
            {:noreply, state}
        end

      {:error, _} ->
        Process.send_after(self(), :connect, @retry_delay)
        {:noreply, state}
    end
  end

  def handle_info(:keepalive_received, state) do
    {:noreply, %{state | ready?: true}}
  end

  def handle_info({:session_down, reason}, state) do
    Logger.warning("Chronicle session dropped: #{inspect(reason)}, reconnecting...")
    {:noreply, schedule_reconnect(%{state | keepalive_task: nil, ready?: false})}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{keepalive_task: %Task{pid: pid}} = state) do
    Logger.warning("Chronicle session task exited: #{inspect(reason)}")
    {:noreply, schedule_reconnect(%{state | keepalive_task: nil, ready?: false})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp start_session(channel, state) do
    try do
      request = struct(ConnectRequest,
        ConnectionId: state.connection_id,
        ClientVersion: "1.0.0",
        IsRunningWithDebugger: false
      )

      case ConnectionService.Stub.connect(channel, request) do
        {:ok, reply_stream} ->
          handler = self()
          task = Task.async(fn -> keepalive_loop(handler, reply_stream) end)
          {:ok, %{state | keepalive_task: task}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp keepalive_loop(handler, reply_stream) do
    Enum.each(reply_stream, fn
      {:ok, _keepalive} ->
        send(handler, :keepalive_received)

      {:error, reason} ->
        send(handler, {:session_down, reason})
    end)
  end

  defp schedule_reconnect(state) do
    Process.send_after(self(), :connect, @retry_delay)
    state
  end

  defp name_for(nil), do: __MODULE__
  defp name_for(client_name), do: :"#{client_name}.Session"

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
