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
      projection/read-model observer on the `event-log` sequence whose id is no longer
      declared by any current artifact. Always `:info`: an event store can be shared by
      several clients, and their observers are also client-owned, so this is evidence only,
      never a reason to fail startup.
    * `:observer_event_types_changed` — a still-declared observer's handled event type ids no
      longer match what the kernel has recorded for it.

  Does not decide what to do about a finding — `drift_policy` on `Chronicle.Client` and
  `Chronicle.Registration.Coordinator` do that.
  """

  alias Chronicle.Discovery.{Artifact, Drift, EventSchemaShape, Report}
  alias Chronicle.Schemas.JsonSchemaGenerator
  alias Chronicle.WireResult

  alias Cratis.Chronicle.Contracts.EventTypes.{
    AllEventTypeGenerationsRequest,
    AllEventTypesRequest,
    EventTypes
  }

  alias Cratis.Chronicle.Contracts.Observation.{AllObserversRequest, Observers}

  @deadline 5_000
  @max_concurrency 8
  @local_event_sequence "event-log"

  @doc """
  Detects likely artifact identity drift for the given report.

  `opts` requires `:event_store` and accepts `:namespace` (default `"Default"`). Returns
  `{:ok, findings}` (possibly empty) or `{:error, reason}` when the kernel could not be
  reached — an indeterminate result, never to be treated the same as a clean one.

  The check makes one `AllEventTypes` call, then `AllEventTypeGenerations` only for event
  types whose local generation is not the kernel's latest (bounded-parallel), all within a
  total deadline (5 seconds, `:deadline` in milliseconds) after which it returns
  `{:error, :timeout}`. A raise inside the check is returned as
  `{:error, {:exception, exception}}`.

  `:fetch_all_event_types_fun`, `:fetch_event_type_generations_fun` and
  `:fetch_observers_fun` are test-only seams replacing the real kernel calls; production
  code never passes them.
  """
  @spec detect(term(), Report.t(), keyword()) :: {:ok, [Drift.t()]} | {:error, term()}
  def detect(channel, %Report{} = report, opts) do
    deadline = Keyword.get(opts, :deadline, @deadline)

    task =
      Task.async(fn ->
        try do
          do_detect(channel, report, opts, deadline)
        rescue
          exception -> {:error, {:exception, exception}}
        end
      end)

    case Task.yield(task, deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  defp do_detect(channel, report, opts, deadline) do
    event_store = Keyword.fetch!(opts, :event_store)
    namespace = Keyword.get(opts, :namespace, "Default")

    funs = %{
      all_event_types: Keyword.get(opts, :fetch_all_event_types_fun, &fetch_all_event_types/2),
      generations:
        Keyword.get(opts, :fetch_event_type_generations_fun, &fetch_event_type_generations/3)
    }

    fetch_observers_fun = Keyword.get(opts, :fetch_observers_fun, &fetch_observers/3)

    with {:ok, observers} <- fetch_observers_fun.(channel, event_store, namespace),
         {:ok, schema_drift} <- schema_drift(channel, event_store, report, funs, deadline) do
      {:ok, schema_drift ++ observer_drift(observers, report)}
    end
  end

  # One `AllEventTypes` call carries the latest generation and schema of every type. A
  # per-type `AllEventTypeGenerations` call is only needed when the local generation is not
  # the latest one the kernel has.
  defp schema_drift(channel, event_store, report, funs, deadline) do
    artifacts = Report.of_kind(report, :event_type)

    with {:ok, all} <- funs.all_event_types.(channel, event_store) do
      latest = Map.new(all, &{&1."Type"."Id", &1})

      older_ids =
        artifacts
        |> Enum.filter(fn artifact ->
          case Map.fetch(latest, artifact.id) do
            {:ok, stored} -> stored."Type"."Generation" != artifact.generation
            :error -> false
          end
        end)
        |> Enum.map(& &1.id)
        |> Enum.uniq()

      with {:ok, loaded} <-
             load_generations(channel, event_store, older_ids, funs.generations, deadline) do
        {:ok,
         Enum.flat_map(artifacts, fn artifact ->
           stored_generations =
             case Map.fetch(loaded, artifact.id) do
               {:ok, generations} -> generations
               :error -> List.wrap(Map.get(latest, artifact.id))
             end

           schema_drift_for_artifact(artifact, stored_generations)
         end)}
      end
    end
  end

  defp load_generations(_channel, _event_store, [], _fun, _deadline), do: {:ok, %{}}

  defp load_generations(channel, event_store, ids, fun, deadline) do
    ids
    |> Task.async_stream(fn id -> {id, fun.(channel, event_store, id)} end,
      max_concurrency: @max_concurrency,
      timeout: deadline,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {id, {:ok, generations}}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, id, generations)}}
      {:ok, {_id, {:error, reason}}}, _acc -> {:halt, {:error, reason}}
      {:exit, _reason}, _acc -> {:halt, {:error, :timeout}}
    end)
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
    # Local reactors, reducers and projections all observe the event log; an observer on
    # another sequence belongs to some other client or concern.
    |> Enum.filter(&(&1.event_sequence_id in [@local_event_sequence, "", nil]))
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
            severity: :info
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
    top_level =
      [:from, :join, :removed_with, :removed_with_join, :enters_on]
      |> Enum.flat_map(fn key ->
        apply(module, introspection_fun, [key]) |> Enum.map(&elem(&1, 0))
      end)

    # `from_every` maps properties for every event and names no event type of its own.
    (top_level ++ child_events(apply(module, introspection_fun, [:children])))
    |> Enum.map(& &1.__chronicle_event_type__(:id))
    |> Enum.uniq()
  end

  defp child_events(children) do
    Enum.flat_map(children, fn {_name, _opts, declarations} ->
      Enum.flat_map(declarations, fn
        {kind, event, _opts} when kind in [:from, :join, :removed_with, :removed_with_join] ->
          [event]

        {:children, name, opts, nested} ->
          child_events([{name, opts, nested}])

        _other ->
          []
      end)
    end)
  end

  defp fetch_all_event_types(channel, event_store) do
    request = struct(AllEventTypesRequest, EventStore: event_store)

    case EventTypes.Stub.all_event_types(channel, request) do
      {:ok, envelope} -> WireResult.unwrap(envelope)
      {:error, reason} -> {:error, reason}
    end
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
