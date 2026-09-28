# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Transport do
  @moduledoc false

  # grpc 1.x also offers Connection.start_link/2 for supervision outside its
  # global DynamicSupervisor. Own those children here so an owner killed while
  # blocked in a callback cannot leave a globally supervised channel behind.
  use GenServer

  @connect_timeout 15_000
  @connected_event [:grpc, :client, :connection, :connected]
  @connect_error_event [:grpc, :client, :connection, :connect_error]

  def start(owner), do: GenServer.start(__MODULE__, owner)

  def connect(transport, target, opts) do
    supervisor = GenServer.call(transport, :supervisor)
    opts = Keyword.put_new_lazy(opts, :name, &make_ref/0)
    name = opts[:name]

    # Chronicle handles reconnection. A crashed orchestrator must not restart
    # behind its back while it is releasing the old channel.
    spec = %{
      GRPC.Client.Connection.child_spec({target, opts})
      | restart: :temporary,
        shutdown: 1_000
    }

    # Subscribe before starting the child: grpc emits its first establishment
    # result through its public telemetry events. Unlike await_ready/2, this
    # preserves Stub.connect/2's fail-fast first-attempt behavior.
    handler = make_ref()
    caller = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [@connected_event, @connect_error_event],
        &__MODULE__.handle_dial_event/4,
        {caller, handler, name}
      )

    try do
      case DynamicSupervisor.start_child(supervisor, spec) do
        {:ok, pid} ->
          result =
            with :ok <-
                   wait_for_first_attempt(
                     pid,
                     handler,
                     opts[:connect_timeout] || @connect_timeout
                   ),
                 {:ok, channel} <- GRPC.Client.Connection.pick_channel(%GRPC.Channel{ref: name}),
                 :ok <- GenServer.call(transport, {:track, name, pid, channel}) do
              {:ok, channel}
            end

          if not match?({:ok, _}, result) do
            release_child(supervisor, pid, nil)
            # A child that died before it was tracked leaves grpc's entries behind.
            erase_grpc_entries(name)
          end

          result

        {:error, reason} ->
          {:error, reason}
      end
    after
      :telemetry.detach(handler)
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc false
  def handle_dial_event(event, _measurements, metadata, {caller, handler, name}) do
    if metadata.name == name, do: send(caller, {:grpc_dial, handler, event, metadata})
  end

  def release(transport, %GRPC.Channel{ref: ref}) do
    GenServer.call(transport, {:release, ref})
  end

  @impl true
  def init(owner) do
    Process.monitor(owner)
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    {:ok, %{owner: owner, supervisor: supervisor, channels: %{}}}
  end

  @impl true
  def handle_call(:supervisor, _from, state), do: {:reply, state.supervisor, state}

  def handle_call({:track, ref, pid, channel}, _from, state) do
    socket = socket_for(channel)
    Process.monitor(pid)
    {:reply, :ok, %{state | channels: Map.put(state.channels, ref, {pid, socket})}}
  end

  def handle_call({:release, ref}, _from, state) do
    case Map.pop(state.channels, ref) do
      {nil, _} ->
        {:reply, :not_owned, state}

      {{pid, socket}, channels} ->
        release_child(state.supervisor, pid, socket)
        # The child may have crashed while being released; its DOWN would then match nothing.
        erase_grpc_entries(ref)
        {:reply, :ok, %{state | channels: channels}}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, owner, _}, %{owner: owner} = state) do
    # Stopping the supervisor removes every child spec, including a dial still
    # in progress. Close Mint sockets even if an orchestrator skipped terminate.
    Enum.each(state.channels, fn {_, {_pid, socket}} -> close_socket(socket) end)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, pid, reason}, state) do
    Enum.each(state.channels, fn {ref, {child, _}} ->
      if child == pid do
        # grpc 1.0.5 keeps the channel and load-balancer state in node-wide
        # :persistent_term entries and only erases them on a normal shutdown,
        # expecting a restart otherwise. Children here are :temporary and never
        # restart, so erase the entries ourselves (keys: Connection's private
        # channel_key/1 and lb_key/1, pinned by a spec).
        if not normal_exit?(reason), do: erase_grpc_entries(ref)
        send(state.owner, {:grpc_transport_down, ref})
      end
    end)

    {:noreply, state}
  end

  defp normal_exit?(reason), do: reason in [:normal, :shutdown] or match?({:shutdown, _}, reason)

  @doc false
  def erase_grpc_entries(ref) do
    :persistent_term.erase({GRPC.Client.Connection, :channel, ref})
    :persistent_term.erase({GRPC.Client.Connection, :lb, ref})
    :ok
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.channels, fn {_, {_pid, socket}} -> close_socket(socket) end)
    # Linked DynamicSupervisor shuts down its children when we exit normally
    # only if stopped explicitly (:normal link exits are otherwise ignored).
    if Process.alive?(state.supervisor), do: Supervisor.stop(state.supervisor, :normal, 2_000)
    :ok
  end

  defp wait_for_first_attempt(pid, handler, timeout) do
    monitor = Process.monitor(pid)

    try do
      receive do
        {:grpc_dial, ^handler, @connected_event, _} -> :ok
        {:grpc_dial, ^handler, @connect_error_event, %{reason: reason}} -> {:error, reason}
        {:DOWN, ^monitor, :process, ^pid, reason} -> {:error, reason}
      after
        timeout -> {:error, :timeout}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp release_child(supervisor, pid, socket) do
    try do
      DynamicSupervisor.terminate_child(supervisor, pid)
    catch
      :exit, _ -> :ok
    after
      close_socket(socket)
    end
  end

  defp socket_for(%{adapter_payload: %{conn_pid: socket}}), do: socket
  defp socket_for(_), do: nil

  defp close_socket(socket) when is_pid(socket) do
    if Process.alive?(socket), do: Process.exit(socket, :kill)
  end

  defp close_socket(_), do: :ok
end
