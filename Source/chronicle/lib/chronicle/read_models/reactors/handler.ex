# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Reactors.Handler do
  @moduledoc false

  # Subscribes to one read model for a `Chronicle.ReadModels.Reactor` module and dispatches its
  # changes to the module's callbacks. The subscription is established through
  # `Chronicle.ReadModels.subscribe/2`, which shares its kernel stream with any other subscriber of
  # the same read model (including other read model reactors), and is (re)established whenever the
  # client reaches `:registered`. Reconnection after a stream failure, and the backoff between
  # attempts, is the shared watcher's job - this handler only logs what it is told.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.ReadModels

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)

    state = %{
      module: module,
      model: module.__chronicle_read_model_reactor__(:model),
      client: Keyword.get(opts, :client, Chronicle.Client),
      lifecycle: Keyword.get(opts, :lifecycle),
      event_sequence_id: module.__chronicle_read_model_reactor__(:event_sequence_id),
      watcher: nil
    }

    if state.lifecycle, do: Lifecycle.subscribe(state.lifecycle)
    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, :registered, _id}, state), do: {:noreply, watch(state)}

  def handle_info({:chronicle_lifecycle, :disconnected, _id}, state),
    do: {:noreply, unwatch(state)}

  def handle_info({:chronicle_lifecycle, _phase, _id}, state), do: {:noreply, state}

  def handle_info({:chronicle_read_model_changed, model, changeset}, %{model: model} = state) do
    dispatch(state.module, changeset)
    {:noreply, state}
  end

  def handle_info({:chronicle_read_model_watch_ended, model, reason}, %{model: model} = state) do
    Logger.warning(
      "Read model reactor #{state.module.__chronicle_read_model_reactor__(:id)} lost its shared " <>
        "watch: #{inspect(reason)}; it resumes automatically"
    )

    {:noreply, state}
  end

  def handle_info({:chronicle_read_model_watch_resumed, model}, %{model: model} = state) do
    Logger.info(
      "Read model reactor #{state.module.__chronicle_read_model_reactor__(:id)} watch resumed"
    )

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  # Routes a change to the matching optional callback. Public so it can be specified without a
  # connection.
  def dispatch(module, changeset) do
    {callback, argument} =
      case changeset.change_type do
        :added -> {:on_added, changeset.read_model}
        :modified -> {:on_modified, changeset.read_model}
        :removed -> {:on_removed, changeset.model_key}
      end

    if function_exported?(module, callback, 2) do
      try do
        apply(module, callback, [argument, changeset])
      rescue
        error ->
          Logger.error(
            "Read model reactor #{inspect(module)}.#{callback}/2 raised: " <>
              Exception.format(:error, error, __STACKTRACE__)
          )
      end
    end

    :ok
  end

  defp watch(state) do
    state = unwatch(state)

    case ReadModels.subscribe(state.model,
           client: state.client,
           event_sequence_id: state.event_sequence_id
         ) do
      {:ok, watcher} ->
        %{state | watcher: watcher}

      {:error, reason} ->
        Logger.warning(
          "Read model reactor #{state.module.__chronicle_read_model_reactor__(:id)} could not " <>
            "subscribe: #{inspect(reason)}"
        )

        state
    end
  end

  defp unwatch(%{watcher: nil} = state), do: state

  defp unwatch(%{watcher: watcher} = state) do
    ReadModels.unsubscribe(watcher)
    %{state | watcher: nil}
  end
end
