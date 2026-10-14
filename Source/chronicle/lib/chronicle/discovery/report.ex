# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.Report do
  @moduledoc """
  What the client found, across every artifact kind `Chronicle.Artifacts` knows how to
  discover: event types, event sources, reactors, reducers, declarative projections, read
  models, constraints, webhooks, event store subscriptions, seeders, migrations, global
  handlers and captures.

  Built by `Chronicle.Client` at startup (`Chronicle.Client.discovery_report/1`), by
  `Chronicle.Artifacts.report/1`, and by `mix chronicle.discover`.
  """

  alias Chronicle.Discovery.{Artifact, DefaultedIdWarning}

  @enforce_keys [:has_run, :artifacts]
  defstruct has_run: false, artifacts: []

  @type t :: %__MODULE__{has_run: boolean(), artifacts: [Artifact.t()]}

  @doc """
  The report before discovery has completed.
  """
  @spec not_run() :: t()
  def not_run, do: %__MODULE__{has_run: false, artifacts: []}

  @doc """
  Builds a report from discovered or explicitly configured artifact module lists.

  Accepts a map or keyword list with the same keys `Chronicle.Artifacts.discover/1` and
  `Chronicle.Client`'s options use: `:event_types`, `:event_sources`, `:reactors`,
  `:reducers`, `:projections`, `:read_models`, `:constraints`, `:webhooks`,
  `:event_store_subscriptions`, `:seeders`, `:migrations`, `:global_handlers`, `:captures`.
  Every key is optional and defaults to `[]`.

  `:warn_defaulted_ids` (default `true`) controls whether a reactor, reducer or projection
  whose id defaults to its module name emits the one-time warning described on
  `Chronicle.Discovery.DefaultedIdWarning`.
  """
  @spec build(map() | keyword()) :: t()
  def build(artifacts \\ %{}) do
    artifacts = Map.new(artifacts)
    warn? = Map.get(artifacts, :warn_defaulted_ids, true)

    built =
      event_type_artifacts(get(artifacts, :event_types)) ++
        simple_artifacts(
          :event_source,
          get(artifacts, :event_sources),
          :__chronicle_event_source__,
          :name
        ) ++
        observer_artifacts(:reactor, get(artifacts, :reactors), :__chronicle_reactor__, warn?) ++
        observer_artifacts(:reducer, get(artifacts, :reducers), :__chronicle_reducer__, warn?) ++
        observer_artifacts(
          :projection,
          get(artifacts, :projections),
          :__chronicle_projection__,
          warn?
        ) ++
        simple_artifacts(
          :read_model,
          get(artifacts, :read_models),
          :__chronicle_read_model__,
          :id
        ) ++
        constraint_artifacts(get(artifacts, :constraints)) ++
        simple_artifacts(:webhook, get(artifacts, :webhooks), :__chronicle_webhook__, :id) ++
        simple_artifacts(
          :event_store_subscription,
          get(artifacts, :event_store_subscriptions),
          :__chronicle_event_store_subscription__,
          :id
        ) ++
        simple_artifacts(:seeder, get(artifacts, :seeders), :__chronicle_seeder__, :id) ++
        migration_artifacts(get(artifacts, :migrations)) ++
        global_handler_artifacts(get(artifacts, :global_handlers)) ++
        simple_artifacts(:capture, get(artifacts, :captures), :__chronicle_capture__, :id)

    %__MODULE__{
      has_run: true,
      artifacts: Enum.sort_by(built, &{&1.kind, &1.id, &1.generation || 0})
    }
  end

  @doc """
  Selects artifacts of a given kind.
  """
  @spec of_kind(t(), Artifact.kind()) :: [Artifact.t()]
  def of_kind(%__MODULE__{artifacts: artifacts}, kind),
    do: Enum.filter(artifacts, &(&1.kind == kind))

  @doc """
  Counts artifacts of a given kind.
  """
  @spec count_of(t(), Artifact.kind()) :: non_neg_integer()
  def count_of(%__MODULE__{} = report, kind), do: report |> of_kind(kind) |> length()

  @doc """
  A one-line, per-kind count summary — suitable for an info-level log line.
  """
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{has_run: false}), do: "not run"

  def summary(%__MODULE__{} = report) do
    kinds()
    |> Enum.map(fn kind -> "#{count_of(report, kind)} #{plural(kind)}" end)
    |> Enum.join(", ")
  end

  @doc """
  A full, multi-line rendering of every artifact grouped by kind — suitable for a debug-level
  log line or `mix chronicle.discover`'s output.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{has_run: false}), do: "Chronicle discovery report: not run"

  def format(%__MODULE__{} = report) do
    lines =
      kinds()
      |> Enum.map(fn kind -> format_kind(kind, of_kind(report, kind)) end)

    Enum.join(["Chronicle discovery report:" | lines], "\n")
  end

  defp format_kind(kind, []), do: "  #{plural(kind)} (0)"

  defp format_kind(kind, artifacts) do
    ids = Enum.map(artifacts, &format_artifact/1)
    "  #{plural(kind)} (#{length(artifacts)}): #{Enum.join(ids, ", ")}"
  end

  defp format_artifact(%Artifact{generation: nil} = artifact), do: artifact.id
  defp format_artifact(%Artifact{} = artifact), do: "#{artifact.id} (gen #{artifact.generation})"

  defp kinds do
    [
      :event_type,
      :event_source,
      :reactor,
      :reducer,
      :projection,
      :read_model,
      :constraint,
      :webhook,
      :event_store_subscription,
      :seeder,
      :migration,
      :global_handler,
      :capture
    ]
  end

  defp plural(:event_type), do: "event types"
  defp plural(:event_source), do: "event sources"
  defp plural(:reactor), do: "reactors"
  defp plural(:reducer), do: "reducers"
  defp plural(:projection), do: "projections"
  defp plural(:read_model), do: "read models"
  defp plural(:constraint), do: "constraints"
  defp plural(:webhook), do: "webhooks"
  defp plural(:event_store_subscription), do: "event store subscriptions"
  defp plural(:seeder), do: "seeders"
  defp plural(:migration), do: "migrations"
  defp plural(:global_handler), do: "global handlers"
  defp plural(:capture), do: "captures"

  defp get(artifacts, key), do: Map.get(artifacts, key, [])

  defp event_type_artifacts(modules) do
    Enum.map(modules, fn module ->
      %Artifact{
        kind: :event_type,
        module: module,
        id: module.__chronicle_event_type__(:id),
        generation: module.__chronicle_event_type__(:generation),
        id_source: :explicit
      }
    end)
  end

  defp observer_artifacts(kind, modules, introspection_fun, warn?) do
    Enum.map(modules, fn module ->
      id_source = apply(module, introspection_fun, [:id_source])

      if id_source == :module_name do
        DefaultedIdWarning.warn_once(module, kind, warn?)
      end

      %Artifact{
        kind: kind,
        module: module,
        id: apply(module, introspection_fun, [:id]),
        id_source: id_source
      }
    end)
  end

  defp simple_artifacts(kind, modules, introspection_fun, id_key) do
    Enum.map(modules, fn module ->
      %Artifact{
        kind: kind,
        module: module,
        id: to_string(apply(module, introspection_fun, [id_key]))
      }
    end)
  end

  defp constraint_artifacts(modules) do
    Enum.flat_map(modules, fn module ->
      module.__chronicle_constraint__(:definitions)
      |> Enum.map(fn definition ->
        %Artifact{
          kind: :constraint,
          module: module,
          id: Map.get(definition, :name, inspect(module)),
          id_source: :explicit
        }
      end)
    end)
  end

  defp migration_artifacts(modules) do
    Enum.map(modules, fn module ->
      %Artifact{
        kind: :migration,
        module: module,
        id: module.__chronicle_migration__(:event_type_id),
        generation: module.__chronicle_migration__(:to_generation),
        id_source: :explicit
      }
    end)
  end

  defp global_handler_artifacts(modules) do
    Enum.map(modules, fn module ->
      %Artifact{
        kind: :global_handler,
        module: module,
        id: inspect(module.__chronicle_global_handler__(:identity))
      }
    end)
  end
end
