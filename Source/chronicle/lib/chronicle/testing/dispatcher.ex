# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Dispatcher do
  @moduledoc false

  # Subscribes to a Chronicle.Testing.InMemoryKernel's committed append batches and
  # runs every registered reactor and reducer against them synchronously, in this
  # process (never inside the kernel's own GenServer, so a reactor's own append —
  # which goes back through the real client and the kernel — can never deadlock
  # it). A reducer's resulting read model state is kept here, per
  # {reducer_module, key}, for Chronicle.Testing.read_model/3.
  #
  # Because this process receives the kernel's {:chronicle_testing_appended, ...}
  # broadcast as an ordinary message, and GenServer processes its mailbox in
  # order, a plain `GenServer.call/2` sent after an append is a deterministic,
  # sleep-free barrier: it can only be answered once every batch sent before it
  # has already been handled (see Chronicle.Testing.wait_for_observers/1).

  use GenServer

  require Logger

  alias Chronicle.Reactors.Dispatch, as: ReactorDispatch
  alias Chronicle.Reducers.Dispatch, as: ReducerDispatch

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec ping(GenServer.server()) :: :ok
  def ping(dispatcher), do: GenServer.call(dispatcher, :ping, :infinity)

  @spec read_model(GenServer.server(), module(), String.t()) :: {:ok, struct() | nil}
  def read_model(dispatcher, reducer_module, key),
    do: GenServer.call(dispatcher, {:read_model, reducer_module, key})

  @spec failures(GenServer.server()) :: [term()]
  def failures(dispatcher), do: GenServer.call(dispatcher, :failures)

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    reactor_states =
      opts
      |> Keyword.get(:reactors, [])
      |> Map.new(fn module -> {module, reactor_state(module, client)} end)

    reducer_states =
      opts
      |> Keyword.get(:reducers, [])
      |> Map.new(fn module -> {module, reducer_state(module)} end)

    {:ok,
     %{
       client: client,
       reactors: reactor_states,
       reducers: reducer_states,
       models: %{},
       failures: []
     }}
  end

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :ok, state}

  def handle_call({:read_model, reducer_module, key}, _from, state) do
    {:reply, {:ok, Map.get(state.models, {reducer_module, key})}, state}
  end

  def handle_call(:failures, _from, state), do: {:reply, Enum.reverse(state.failures), state}

  @impl true
  def handle_info({:chronicle_testing_appended, _es, _ns, _seq_id, events}, state) do
    state =
      state
      |> run_reactors(events)
      |> run_reducers(events)

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp run_reactors(state, events) do
    Enum.reduce(state.reactors, state, fn {_module, reactor_state}, state ->
      Enum.reduce(events, state, fn event, state ->
        case ReactorDispatch.dispatch_event(reactor_state, event) do
          :ok -> state
          {:error, reason} -> record_failure(state, {:reactor, reactor_state.module, reason})
        end
      end)
    end)
  end

  defp run_reducers(state, events) do
    by_source = Enum.group_by(events, &get_in(&1, [:Context, :EventSourceId]))

    Enum.reduce(state.reducers, state, fn {module, reducer_state}, state ->
      Enum.reduce(by_source, state, fn {event_source_id, source_events}, state ->
        relevant =
          Enum.filter(source_events, fn event ->
            event_type_id = get_in(event, [:Context, :EventType, :Id])
            Map.has_key?(reducer_state.event_type_map, event_type_id)
          end)

        if relevant == [] do
          state
        else
          apply_reducer(state, module, reducer_state, event_source_id, relevant)
        end
      end)
    end)
  end

  defp apply_reducer(state, module, reducer_state, event_source_id, events) do
    previous = Map.get(state.models, {module, event_source_id})

    initial_state_json =
      case previous do
        nil -> ""
        model -> Chronicle.Serialization.to_json(model, :identity)
      end

    reduce_op = %{Partition: "", InitialState: initial_state_json, Events: events}

    case ReducerDispatch.build_result_and_model(reducer_state, reduce_op) do
      {_message, final_model} ->
        %{state | models: Map.put(state.models, {module, event_source_id}, final_model)}
    end
  rescue
    e -> record_failure(state, {:reducer, module, e})
  end

  defp record_failure(state, failure) do
    Logger.warning("Chronicle.Testing.Dispatcher: #{inspect(failure)}")
    %{state | failures: [failure | state.failures]}
  end

  defp reactor_state(module, client) do
    event_type_modules = module.__chronicle_reactor__(:handles)

    event_type_map =
      Map.new(event_type_modules, fn et_module ->
        {et_module.__chronicle_event_type__(:id), et_module}
      end)

    %{
      module: module,
      event_type_map: event_type_map,
      append_fun: fn operation -> ReactorDispatch.default_append(operation, client) end
    }
  end

  defp reducer_state(module) do
    event_type_modules = module.__chronicle_reducer__(:handles)

    event_type_map =
      Map.new(event_type_modules, fn et_module ->
        {et_module.__chronicle_event_type__(:id), et_module}
      end)

    %{
      module: module,
      event_type_map: event_type_map,
      model_module: module.__chronicle_reducer__(:model)
    }
  end
end
