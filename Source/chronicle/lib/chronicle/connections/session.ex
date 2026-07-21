# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Session do
  @moduledoc false

  # Establishes and maintains a Chronicle client session via
  # ConnectionService.Connect. Chronicle requires a client to register its
  # ConnectionId before reactors or reducers can register observers.
  #
  # The server registers the client asynchronously in a Task.Run AFTER returning
  # the Connect stream, and only sends the first keepalive AFTER that registration
  # completes (plus ~1 second). So `ready?` is set to true on the first keepalive,
  # and observers (reactors/reducers) must wait until then before registering.
  #
  # Liveness is a two-way contract. `Chronicle.Connections.KeepAlive` answers
  # every keepalive the kernel pushes, and the watchdog here treats a gap longer
  # than @keepalive_timeout as a dead session. Both halves are needed: the kernel
  # does not close the Connect stream when its own watchdog evicts us, so waiting
  # for a stream error alone leaves a half-open session that looks connected
  # forever while observers receive nothing.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.{Connection, KeepAlive, Lifecycle}

  alias Cratis.Chronicle.Contracts.Clients.{
    ConnectionService,
    ConnectRequest
  }

  @retry_delay 3_000

  # Mirrors the C# client: the kernel emits a keepalive every second and evicts
  # any client whose LastSeen falls more than 5 seconds behind.
  @keepalive_poll_interval 1_000
  @keepalive_timeout 5_000

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
      lifecycle: Keyword.get(opts, :lifecycle),
      connection_id: generate_connection_id(),
      keepalive_task: nil,
      keepalive_fun: Keyword.get(opts, :keepalive_fun, &KeepAlive.answer/2),
      last_keepalive: nil,
      watchdog_timer: nil,
      reconnect_timer: nil,
      ready?: false
    }

    if Keyword.get(opts, :auto_connect, true), do: send(self(), :connect)
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
    state = %{state | reconnect_timer: nil}

    case Connection.channel(state.connection) do
      {:ok, channel} ->
        case start_session(channel, state) do
          {:ok, new_state} ->
            Logger.debug("Chronicle session established: #{new_state.connection_id}")
            {:noreply, new_state}

          {:error, reason} ->
            Logger.warning("Chronicle session failed to start: #{inspect(reason)}, retrying...")
            {:noreply, schedule_reconnect(state)}
        end

      {:error, _} ->
        {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info(:keepalive_received, %{ready?: false} = state) do
    notify_connected(state)
    {:noreply, %{state | ready?: true, last_keepalive: now_ms()}}
  end

  def handle_info(:keepalive_received, state) do
    {:noreply, %{state | last_keepalive: now_ms()}}
  end

  # The kernel leaves the Connect stream open when its watchdog evicts a client,
  # so a silent stream — not an errored one — is the shape a half-disconnect
  # actually takes. Poll for the gap rather than waiting to be told.
  def handle_info(:watchdog, %{last_keepalive: nil} = state), do: {:noreply, state}

  def handle_info(:watchdog, state) do
    if now_ms() - state.last_keepalive > @keepalive_timeout do
      {:noreply, drop_session(state, :keepalive_timeout)}
    else
      {:noreply, %{state | watchdog_timer: start_watchdog()}}
    end
  end

  def handle_info({:session_down, reason}, state) do
    {:noreply, drop_session(state, reason)}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, reason},
        %{keepalive_task: %Task{pid: pid}} = state
      ) do
    {:noreply, drop_session(state, {:task_exited, reason})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp start_session(channel, state) do
    try do
      # The lifecycle owns the connection id and rotates it on every disconnect,
      # so read the current id at connect time to use a fresh one after a drop.
      connection_id = current_connection_id(state)

      request =
        struct(ConnectRequest,
          ConnectionId: connection_id,
          ClientVersion: "1.0.0",
          IsRunningWithDebugger: false,
          ProcessId: process_id(),
          # The BEAM has no reliable way to discover the OS executable path for
          # the running node (unlike a Debugger-attachable process on other
          # platforms), so this is reported empty rather than guessed — the
          # same gap and the same call, decided for the Elixir client.
          ProcessPath: "",
          MachineName: machine_name(),
          ClientType: "Elixir"
        )

      case ConnectionService.Stub.connect(channel, request) do
        {:ok, reply_stream} ->
          handler = self()
          keepalive_fun = state.keepalive_fun

          task =
            Task.async(fn ->
              KeepAlive.run(handler, reply_stream, channel, connection_id, keepalive_fun)
            end)

          {:ok,
           %{
             state
             | keepalive_task: task,
               connection_id: connection_id,
               last_keepalive: now_ms(),
               watchdog_timer: start_watchdog()
           }}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  # Tears the session down and schedules a fresh connect. Safe to call more than
  # once per drop: both the keepalive loop and the task monitor can report the
  # same failure, and only the first one gets to schedule a reconnect.
  defp drop_session(state, reason) do
    if state.keepalive_task || state.watchdog_timer do
      Logger.warning("Chronicle session dropped: #{inspect(reason)}, reconnecting...")
    end

    notify_disconnected(state)

    state
    |> teardown()
    |> schedule_reconnect()
  end

  defp teardown(state) do
    shutdown_task(state.keepalive_task)
    cancel_timer(state.watchdog_timer)

    %{state | keepalive_task: nil, watchdog_timer: nil, last_keepalive: nil, ready?: false}
  end

  defp current_connection_id(%{lifecycle: nil, connection_id: connection_id}), do: connection_id
  defp current_connection_id(%{lifecycle: lifecycle}), do: Lifecycle.connection_id(lifecycle)

  defp notify_connected(%{lifecycle: nil}), do: :ok

  defp notify_connected(%{lifecycle: lifecycle, connection_id: connection_id}) do
    Lifecycle.connected(lifecycle, connection_id)
  end

  # Only report a disconnect for a session that actually came up, so repeated
  # failed connect attempts don't spam observers with teardown notifications.
  defp notify_disconnected(%{ready?: false}), do: :ok
  defp notify_disconnected(%{lifecycle: nil}), do: :ok
  defp notify_disconnected(%{lifecycle: lifecycle}), do: Lifecycle.disconnected(lifecycle)

  defp start_watchdog do
    Process.send_after(self(), :watchdog, @keepalive_poll_interval)
  end

  defp schedule_reconnect(%{reconnect_timer: timer} = state) when not is_nil(timer), do: state

  defp schedule_reconnect(state) do
    %{state | reconnect_timer: Process.send_after(self(), :connect, @retry_delay)}
  end

  defp shutdown_task(nil), do: :ok
  defp shutdown_task(%Task{} = task), do: Task.shutdown(task, :brutal_kill)
  defp shutdown_task(_), do: :ok

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp name_for(nil), do: __MODULE__
  defp name_for(client_name), do: :"#{client_name}.Session"

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp process_id do
    :os.getpid() |> List.to_integer()
  end

  defp machine_name do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      {:error, _reason} -> ""
    end
  end
end
