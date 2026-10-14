# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Watchers do
  @moduledoc false

  # Shares one kernel `Watch` stream per read model across every caller of
  # `Chronicle.ReadModels.subscribe/2`, instead of each caller opening its own stream the way
  # `Chronicle.ReadModels.watch/2` does.
  #
  # A `Chronicle.Client` starts one of these per client name. A `Registry` maps
  # `{namespace, model_module, event_sequence_id}` to the `Chronicle.ReadModels.Watchers.Watcher`
  # GenServer that owns the stream for that key, started on demand under a `DynamicSupervisor`.

  use Supervisor

  alias Chronicle.ReadModels.Watchers.Watcher

  @doc false
  def start_link(opts) do
    client = Keyword.fetch!(opts, :client)
    Supervisor.start_link(__MODULE__, opts, name: name_for(client))
  end

  @doc false
  @spec name_for(atom()) :: atom()
  def name_for(client), do: :"#{client}.ReadModelWatchers"

  defp registry_for(client), do: :"#{client}.ReadModelWatchers.Registry"
  defp supervisor_for(client), do: :"#{client}.ReadModelWatchers.Supervisor"

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    children = [
      {Registry, keys: :unique, name: registry_for(client)},
      {DynamicSupervisor, name: supervisor_for(client), strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Subscribes the calling process to the shared watch for `model_module`, starting it if no
  other subscriber already has one. Returns `{:ok, watcher}` — pass `watcher` to `unsubscribe/1`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence identifier (default: `"event-log"`)
  """
  @spec subscribe(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def subscribe(model_module, opts \\ []) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    namespace = Keyword.get(opts, :namespace)
    event_sequence_id = Keyword.get(opts, :event_sequence_id, "event-log")
    key = {namespace, model_module, event_sequence_id}

    with {:ok, watcher} <- ensure_watcher(client, key, model_module, opts) do
      Watcher.subscribe(watcher, self())
    end
  end

  @doc """
  Stops the calling process's subscription started by `subscribe/2`. Once the last subscriber
  leaves, the shared watcher closes its stream.
  """
  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(watcher) when is_pid(watcher), do: Watcher.unsubscribe(watcher, self())

  defp ensure_watcher(client, key, model_module, opts) do
    registry = registry_for(client)

    case Registry.lookup(registry, key) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        {namespace, _model_module, event_sequence_id} = key

        child_opts =
          opts
          |> Keyword.take([:stream_opener, :min_backoff, :max_backoff])
          |> Keyword.merge(
            client: client,
            model_module: model_module,
            namespace: namespace,
            event_sequence_id: event_sequence_id,
            registry: registry,
            key: key
          )

        case DynamicSupervisor.start_child(supervisor_for(client), {Watcher, child_opts}) do
          {:ok, pid} ->
            {:ok, pid}

          :ignore ->
            case Registry.lookup(registry, key) do
              [{pid, _value}] -> {:ok, pid}
              [] -> {:error, :watcher_not_found}
            end

          error ->
            error
        end
    end
  end
end
