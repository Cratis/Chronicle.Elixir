# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.DriftDetector do
  @moduledoc """
  Compares a discovery report with what the kernel already knows, before registration.

  Three kinds of drift are detected:

    * `:schema_changed_without_generation` — a registered event type generation's stored
      schema no longer has the same coarse shape (see `Chronicle.Discovery.EventSchemaShape`)
      as the module that currently declares it — its struct changed without a bumped
      `:generation`.
    * `:observer_missing_from_code` — the kernel has a client-owned reactor, reducer or
      projection/read-model observer whose id is no longer declared by any current artifact.
    * `:observer_event_types_changed` — a still-declared observer's handled event type ids no
      longer match what the kernel has recorded for it.

  Does not decide what to do about a finding — `drift_policy` on `Chronicle.Client` and
  `Chronicle.Registration.Coordinator` do that.
  """

  alias Chronicle.Discovery.{Artifact, Drift, EventSchemaShape, Report}
  alias Chronicle.Schemas.JsonSchemaGenerator
  alias Chronicle.WireResult

  alias Cratis.Chronicle.Contracts.EventTypes.{AllEventTypeGenerationsRequest, EventTypes}

  alias Cratis.Chronicle.Contracts.Observation.{AllObserversRequest, Observers}

  @doc """
  Detects likely artifact identity drift for the given report.

  `opts` requires `:event_store` and accepts `:namespace` (default `"Default"`). Returns
  `{:ok, findings}` (possibly empty) or `{:error, reason}` when the kernel could not be
  reached — an indeterminate result, never to be treated the same as a clean one.

  `:fetch_event_type_generations_fun` and `:fetch_observers_fun` are test-only seams
  replacing the real kernel calls; production code never passes them.
  """
  @spec detect(term(), Report.t(), keyword()) :: {:ok, [Drift.t()]} | {:error, term()}
  def detect(channel, %Report{} = report, opts) do
    event_store = Keyword.fetch!(opts, :event_store)
    namespace = Keyword.get(opts, :namespace, "Default")

    fetch_generations_fun =
      Keyword.get(opts, :fetch_event_type_generations_fun, &fetch_event_type_generations/3)

    fetch_observers_fun = Keyword.get(opts, :fetch_observers_fun, &fetch_observers/3)

    with {:ok, observers} <- fetch_observers_fun.(channel, event_store, namespace),
         {:ok, schema_drift} <- schema_drift(channel, event_store, report, fetch_generations_fun) do
      {:ok, schema_drift ++ observer_drift(observers, report)}
    end
  end

  defp schema_drift(channel, event_store, report, fetch_generations_fun) do
    report
    |> Report.of_kind(:event_type)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn event_type_id, {:ok, acc} ->
      case fetch_generations_fun.(channel, event_store, event_type_id) do
        {:ok, stored_generations} ->
          {:cont, {:ok, acc ++ schema_drift_for(event_type_id, stored_generations, report)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp schema_drift_for(event_type_id, stored_generations, report) do
    report
    |> Report.of_kind(:event_type)
    |> Enum.filter(&(&1.id == event_type_id))
    |> Enum.flat_map(fn artifact -> schema_drift_for_artifact(artifact, stored_generations) end)
  end

  defp schema_drift_for_artifact(artifact, stored_generations) do
    stored = Enum.find(stored_generations, &(&1."Type"."Generation" == artifact.generation))

    with %{} = stored <- stored,
         stored_shape when not is_nil(stored_shape) <- EventSchemaShape.of(stored."Schema"),
         local_shape when not is_nil(local_shape) <-
           EventSchemaShape.of(
             JsonSchemaGenerator.generate(artifact.module, key_transform: :camel)
           ),
         true <- stored_shape != local_shape do
      [
        %Drift{
          kind: :event_type,
          id: "#{artifact.id} (gen #{artifact.generation})",
          reason: :schema_changed_without_generation,
          severity: :warning
        }
      ]
    else
      _ -> []
    end
  end

  defp observer_drift(observers, report) do
    local_by_kind = %{
      reactor: Report.of_kind(report, :reactor),
      reducer: Report.of_kind(report, :reducer),
      projection:
        Report.of_kind(report, :projection) ++
          Enum.filter(Report.of_kind(report, :read_model), &projection_backed?/1)
    }

    observers
    |> Enum.filter(&(&1.type in [:reactor, :reducer, :projection] and &1.owner != :kernel))
    |> Enum.flat_map(fn observer ->
      observer_drift_for(observer, Map.get(local_by_kind, observer.type, []))
    end)
  end

  defp projection_backed?(%Artifact{kind: :read_model, module: module}),
    do: module.__chronicle_read_model__(:has_projection?)

  defp observer_drift_for(observer, locals) do
    case Enum.find(locals, &(&1.id == observer.id)) do
      nil ->
        [
          %Drift{
            kind: observer.type,
            id: observer.id,
            reason: :observer_missing_from_code,
            severity: severity_for(observer.type)
          }
        ]

      artifact ->
        handled = handled_event_type_ids(artifact) |> MapSet.new()
        stored = observer.event_types |> Enum.map(& &1."Id") |> MapSet.new()

        if handled == stored do
          []
        else
          [
            %Drift{
              kind: observer.type,
              id: observer.id,
              reason: :observer_event_types_changed,
              severity: severity_for(observer.type)
            }
          ]
        end
    end
  end

  defp severity_for(:reactor), do: :warning
  defp severity_for(_other), do: :info

  defp handled_event_type_ids(%Artifact{kind: :reactor, module: module}) do
    module.__chronicle_reactor__(:handles)
    |> Enum.map(& &1.__chronicle_event_type__(:id))
    |> Enum.uniq()
  end

  defp handled_event_type_ids(%Artifact{kind: :reducer, module: module}) do
    module.__chronicle_reducer__(:handles)
    |> Enum.map(& &1.__chronicle_event_type__(:id))
    |> Enum.uniq()
  end

  defp handled_event_type_ids(%Artifact{kind: :projection, module: module}),
    do: events_from(module, :__chronicle_projection__)

  defp handled_event_type_ids(%Artifact{kind: :read_model, module: module}),
    do: events_from(module, :__chronicle_read_model__)

  defp events_from(module, introspection_fun) do
    [:from, :join, :removed_with, :removed_with_join, :enters_on]
    |> Enum.flat_map(fn key ->
      apply(module, introspection_fun, [key]) |> Enum.map(&elem(&1, 0))
    end)
    |> Enum.map(& &1.__chronicle_event_type__(:id))
    |> Enum.uniq()
  end

  defp fetch_event_type_generations(channel, event_store, event_type_id) do
    request =
      struct(AllEventTypeGenerationsRequest, EventStore: event_store, EventTypeId: event_type_id)

    case EventTypes.Stub.all_event_type_generations(channel, request) do
      {:ok, envelope} -> WireResult.unwrap(envelope)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_observers(channel, event_store, namespace) do
    request = struct(AllObserversRequest, EventStore: event_store, Namespace: namespace)

    case Observers.Stub.get_observers(channel, request) do
      {:ok, response} ->
        {:ok,
         response
         |> Map.get(:items, [])
         |> Enum.map(&Chronicle.Observers.decode_observer_information/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
