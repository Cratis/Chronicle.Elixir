# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.Dispatch do
  @moduledoc false

  # The event-dispatch logic for a reactor: decoding an appended event, invoking the
  # reactor module's handle/2 (or handle_replay/2), deciding what to do with a returned
  # side-effect event, and appending it. Extracted from Chronicle.Reactors.Handler so
  # Chronicle.Testing.start_supervised_client/1 can run a reactor synchronously against
  # the in-memory kernel, outside any gRPC stream.

  require Logger

  alias Chronicle.Diagnostics.Tracing
  alias Chronicle.EventSequences.{EventForEventSourceId, EventLog}
  alias Chronicle.Observers.{BatchContext, EventBatch, PageMessages, PartitionSettlement}

  alias Cratis.Chronicle.Contracts.Observation.Reactors.{
    PartitionResult,
    ReactorMessage,
    ReactorResult
  }

  alias Cratis.Chronicle.Contracts.Observation.Reactors.OneOf_RegisterReactor_ReactorResult,
    as: OneOf

  @doc """
  Builds the `ReactorMessage` result for one delivery: a single partition from a kernel that
  predates pages, or a page of partitions. Batch functions are called once with the events they
  observe; the other events go to `handle/2` in order, partition by partition. Each partition
  is then settled at its earliest failure or deferral.
  """
  @spec build_result(map(), map()) :: struct()
  def build_result(state, message) do
    encode_result(message, dispatch_page(state, message))
  end

  @doc """
  Dispatches every partition of a delivery and returns how each one settled, in the order of
  the delivery's partitions.
  """
  @spec dispatch_page(map(), map()) :: [PartitionSettlement.outcome()]
  def dispatch_page(state, message) do
    partitions = PageMessages.partitions_of(message)
    functions = Map.get(state, :batch_functions, [])

    batch_ids =
      functions
      |> Enum.flat_map(fn {_name, observed} -> observed end)
      |> MapSet.new(& &1.__chronicle_event_type__(:id))

    batch_problems =
      if functions == [],
        do: [],
        else: run_batches(state, functions, partitions, batch_ids, message)

    per_event_problems =
      Enum.flat_map(partitions, fn partition ->
        partition |> dispatch_partition(state, batch_ids) |> List.wrap()
      end)

    problems = batch_problems ++ per_event_problems

    Enum.map(partitions, fn partition ->
      PartitionSettlement.settle(
        partition.partition,
        Enum.map(partition.events, &PageMessages.sequence_number/1),
        problems
      )
    end)
  end

  @doc """
  Builds a failed `ReactorMessage` result for a delivery that is answered without being
  handled, because the kernel has already stopped waiting for it.
  """
  @spec expired_result(map(), String.t()) :: struct()
  def expired_result(message, reason) do
    outcomes =
      message
      |> PageMessages.partitions_of()
      |> Enum.map(fn partition ->
        %{PartitionSettlement.outcome(partition.partition, :failed, 0) | messages: [reason]}
      end)

    encode_result(message, outcomes)
  end

  defp encode_result(message, outcomes) do
    delivery_id = Map.get(message, :DeliveryId, 0) || 0

    result =
      if PageMessages.paged?(message) do
        struct(ReactorResult,
          DeliveryId: delivery_id,
          Partitions:
            Enum.map(outcomes, &PartitionSettlement.partition_result(PartitionResult, &1))
        )
      else
        [outcome] = outcomes

        struct(ReactorResult,
          Partition: outcome.partition,
          State: PartitionSettlement.legacy_state(outcome),
          LastSuccessfulObservation: outcome.last_successful_observation,
          ExceptionMessages: outcome.messages,
          ExceptionStackTrace: outcome.stack_trace,
          # Echoed so the kernel completes exactly this delivery, not just the oldest one
          # pending for the partition.
          DeliveryId: delivery_id
        )
      end

    struct(ReactorMessage, Content: struct(OneOf, Value1: result))
  end

  # Runs the events of one partition that no batch function observes through handle/2, in
  # order, stopping at the first failure. Returns the problem, or nil.
  defp dispatch_partition(partition, state, batch_ids) do
    partition.events
    |> Enum.reject(&MapSet.member?(batch_ids, PageMessages.event_type_id(&1)))
    |> Enum.reduce_while(nil, fn appended_event, nil ->
      case dispatch_event(state, appended_event) do
        :ok ->
          {:cont, nil}

        {:error, reason} ->
          at = PageMessages.sequence_number(appended_event)
          {:halt, PartitionSettlement.failed(partition.partition, at, reason)}
      end
    end)
  end

  # Calls each batch function once with the page's events of the types it observes, in
  # sequence order, and collects the problems it reports.
  defp run_batches(state, functions, partitions, batch_ids, message) do
    reactor_id = state.module.__chronicle_reactor__(:id)

    context =
      BatchContext.for_message(message,
        observer_id: reactor_id,
        event_store: Map.get(state, :event_store, ""),
        namespace: Map.get(state, :namespace, ""),
        event_sequence_id: "event-log"
      )

    {entries, decode_problems} = decode_batch_events(state, partitions, batch_ids, reactor_id)

    entries =
      entries
      |> Enum.sort_by(fn {_partition, _module, _event, ctx} -> ctx.sequence_number end)
      |> Enum.reject(fn {_partition, module, _event, ctx} ->
        replay_action(state.module, module, replay_context(ctx, context)) == :skip
      end)

    decode_problems ++
      Enum.flat_map(functions, fn {name, observed} ->
        case Enum.filter(entries, fn {_p, module, _e, _c} -> module in observed end) do
          [] -> []
          observed_entries -> invoke_batch(state, name, observed_entries, context)
        end
      end)
  end

  defp decode_batch_events(state, partitions, batch_ids, reactor_id) do
    for partition <- partitions,
        appended_event <- partition.events,
        event_type_id = PageMessages.event_type_id(appended_event),
        MapSet.member?(batch_ids, event_type_id),
        reduce: {[], []} do
      {entries, problems} ->
        module = Map.fetch!(state.event_type_map, event_type_id)
        wire_context = Map.get(appended_event, :Context, %{})

        case decode_event(module, Map.get(appended_event, :Content, "")) do
          {:ok, event} ->
            ctx =
              build_context(wire_context, event_sequence_id: "event-log", reactor_id: reactor_id)

            {[{partition.partition, module, event, ctx} | entries], problems}

          {:error, reason} ->
            at = PageMessages.sequence_number(appended_event)
            problem = PartitionSettlement.failed(partition.partition, at, {:decode, reason})
            {entries, [problem | problems]}
        end
    end
  end

  defp replay_context(ctx, %BatchContext{origin: :replay}), do: %{ctx | replaying?: true}
  defp replay_context(ctx, _context), do: ctx

  defp invoke_batch(state, name, entries, context) do
    batch =
      EventBatch.new(
        Enum.map(entries, fn {partition, _module, event, ctx} -> {partition, event, ctx} end),
        context.can_defer?
      )

    reactor_id = state.module.__chronicle_reactor__(:id)

    result =
      Tracing.with_telemetry_span(
        [:cratis, :chronicle, :client, :reactor, :handle_batch],
        %{reactor_id: reactor_id, function: name, event_count: EventBatch.count(batch)},
        "cratis.chronicle.client.reactor.handle_batch",
        %{
          "cratis.event_sequence.id" => "event-log",
          "cratis.observer.id" => reactor_id,
          kind: :consumer
        },
        fn ->
          try do
            apply(state.module, name, [batch, context])
          rescue
            e -> {:error, e}
          end
        end
      )

    case result do
      :ok ->
        []

      %EventBatch{} = reported ->
        reported |> EventBatch.outcomes() |> Enum.map(&PartitionSettlement.from_batch_outcome/1)

      {:error, reason} ->
        fail_every_partition(batch, reason)

      other ->
        fail_every_partition(
          batch,
          "#{inspect(state.module)}.#{name}/2 returned #{inspect(other)}; a reactor batch function " <>
            "returns :ok, the EventBatch or {:error, reason}, and returning events is not supported"
        )
    end
  end

  defp fail_every_partition(batch, reason) do
    batch.entries
    |> Enum.uniq_by(fn {partition, _event, _ctx} -> partition end)
    |> Enum.map(fn {partition, _event, ctx} ->
      PartitionSettlement.failed(partition, ctx.sequence_number, reason)
    end)
  end

  @doc false
  def dispatch_event(state, appended_event) do
    context = Map.get(appended_event, :Context, %{})
    event_type = Map.get(context, :EventType, %{})
    event_type_id = Map.get(event_type, :Id, "")

    case Map.get(state.event_type_map, event_type_id) do
      nil ->
        :ok

      event_module ->
        ctx =
          build_context(context,
            event_sequence_id: "event-log",
            reactor_id: state.module.__chronicle_reactor__(:id)
          )

        content = Map.get(appended_event, :Content, "")

        case decode_event(event_module, content) do
          {:ok, event} ->
            Tracing.with_telemetry_span(
              [:cratis, :chronicle, :client, :reactor, :handle],
              %{
                reactor_id: state.module.__chronicle_reactor__(:id),
                event_type_id: event_type_id
              },
              "cratis.chronicle.client.reactor.handle",
              %{
                "cratis.event_sequence.id" => "event-log",
                "cratis.event_type.id" => event_type_id,
                "cratis.observer.id" => state.module.__chronicle_reactor__(:id),
                "cratis.correlation_id" => ctx.correlation_id,
                kind: :consumer
              },
              fn ->
                try do
                  middleware = Chronicle.Middleware.for_module(state.module, :reactor)

                  middleware
                  |> Chronicle.Middleware.run(event, ctx, fn event, ctx ->
                    case replay_action(state.module, event_module, ctx) do
                      :skip -> :ok
                      :handle_replay -> state.module.handle_replay(event, ctx)
                      :handle -> state.module.handle(event, ctx)
                    end
                  end)
                  |> handle_result(state, ctx.event_source_id)
                rescue
                  e -> {:error, e}
                end
              end
            )

          {:error, reason} ->
            Logger.warning("Failed to decode event #{event_type_id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  # Normalizes handle/2's return value to :ok | {:error, reason}, appending
  # any returned side-effect event(s) via the triggering event source id (or
  # each EventForEventSourceId's own explicit target). Public (but @doc false)
  # so it can be exercised directly in tests against a minimal state map
  # carrying just :append_fun, without a live connection.
  @doc false
  def handle_result(:ok, _state, _event_source_id), do: :ok
  def handle_result({:error, _reason} = error, _state, _event_source_id), do: error

  def handle_result({:ok, side_effect}, state, event_source_id) do
    side_effect
    |> side_effect_operation(event_source_id)
    |> perform_append(state)
  end

  def handle_result(_other, _state, _event_source_id), do: :ok

  # Translates a handle/2 side-effect return value into an append instruction,
  # a pure decision kept separate from performing the actual append (see
  # perform_append/2) so it can be exercised without a live connection.
  @doc false
  def side_effect_operation(nil, _event_source_id), do: :noop

  def side_effect_operation(%EventForEventSourceId{} = wrapped, _event_source_id) do
    {:append, wrapped.event_source_id, wrapped.event,
     [
       event_source_type: wrapped.event_source_type,
       event_stream_type: wrapped.event_stream_type,
       event_stream_id: wrapped.event_stream_id,
       tags: wrapped.tags,
       subject: wrapped.subject,
       occurred: wrapped.occurred,
       concurrency_scope: wrapped.concurrency_scope,
       causation: wrapped.causation,
       identity: wrapped.identity
     ]
     |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)}
  end

  def side_effect_operation(events, event_source_id) when is_list(events) do
    cond do
      events == [] ->
        :noop

      Enum.all?(events, &match?(%EventForEventSourceId{}, &1)) ->
        {:append_many_for_event_sources, events}

      Enum.any?(events, &match?(%EventForEventSourceId{}, &1)) ->
        normalized =
          Enum.map(events, fn
            %EventForEventSourceId{} = wrapped -> wrapped
            event -> %EventForEventSourceId{event_source_id: event_source_id, event: event}
          end)

        {:append_many_for_event_sources, normalized}

      true ->
        {:append_many, event_source_id, events}
    end
  end

  def side_effect_operation(%_{} = event, event_source_id) do
    {:append, event_source_id, event, []}
  end

  def side_effect_operation(_other, _event_source_id), do: :noop

  defp perform_append(:noop, _state), do: :ok
  defp perform_append(operation, state), do: state.append_fun.(operation)

  @doc false
  def default_append({:append, event_source_id, event, opts}, client) do
    EventLog.append(event_source_id, event, Keyword.put(opts, :client, client))
  end

  def default_append({:append_many, event_source_id, events}, client) do
    EventLog.append_many(event_source_id, events, client: client)
  end

  def default_append({:append_many_for_event_sources, events}, client) do
    EventLog.append_many_for_event_sources(events, client: client)
  end

  defp decode_event(event_module, json_content) do
    case Jason.decode(json_content) do
      {:ok, attrs} when is_map(attrs) ->
        {:ok, Chronicle.Serialization.decode(event_module, attrs, :camel)}

      {:ok, other} ->
        {:error, {:unexpected_content, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # An unset or empty wire value means the event was not appended through a
  # registered event source; no name is invented for it.
  @doc false
  def once_only_class?(module), do: module.__chronicle_reactor__(:once_only) == true

  # What to do with an event delivered while the reactor may be replaying (see
  # Chronicle.Reactors.Reactor): skip handlers marked once-only, prefer handle_replay/2 when the
  # reactor defines it, otherwise handle normally.
  @doc false
  def replay_action(module, event_module, %{replaying?: true}) do
    cond do
      once_only_class?(module) -> :skip
      event_module in once_only_events(module) -> :skip
      function_exported?(module, :handle_replay, 2) -> :handle_replay
      true -> :handle
    end
  end

  def replay_action(_module, _event_module, _context), do: :handle

  defp once_only_events(module) do
    case module.__chronicle_reactor__(:once_only) do
      events when is_list(events) -> events
      _ -> []
    end
  end

  @doc false
  def build_context(ctx, opts \\ []), do: Chronicle.Events.EventContext.from_wire(ctx, opts)
end
