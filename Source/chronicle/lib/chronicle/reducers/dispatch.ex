# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.Dispatch do
  @moduledoc false

  # The event-dispatch logic for a reducer: decoding the initial read model state,
  # applying reduce/3 for each event in a batch, and encoding the resulting read
  # model state. Extracted from Chronicle.Reducers.Handler so
  # Chronicle.Testing.start_supervised_client/1 can run a reducer synchronously
  # against the in-memory kernel, outside any gRPC stream.

  require Logger

  alias Chronicle.Diagnostics.Tracing

  alias Chronicle.Observers.{
    BatchContext,
    DeferralNotSupportedByKernel,
    EventBatch,
    PageMessages,
    PartitionSettlement
  }

  alias Cratis.Chronicle.Contracts.Observation.Reducers.{
    PartitionResult,
    ReducerMessage,
    ReducerResult
  }

  @batch_return_shape "a reducer batch function returns the next read model, nil, " <>
                        "{:defer, retry_after_ms}, {:error, reason} or the EventBatch with a " <>
                        "failure or deferral"

  alias Cratis.Chronicle.Contracts.Observation.Reducers.OneOf_RegisterReducer_ReducerResult,
    as: OneOf

  @doc """
  Builds the `ReducerMessage` result for one delivery: a single read model from a kernel that
  predates pages, or a page of read models (partitions). Each partition is reduced on its own,
  from its initial state, with `reduce/3` for each event or with the reducer's batch function;
  the partitions of a page are reduced concurrently, up to the reducer's `:max_concurrency`.
  """
  @spec build_result(map(), map()) :: struct()
  def build_result(state, reduce_op) do
    {message, _models} = build_result_and_models(state, reduce_op)
    message
  end

  @doc """
  Same as `build_result/2` for a single-partition operation, but also returns the final
  (decoded) read model struct — used by `Chronicle.Testing` to keep in-memory reducer state
  without a round trip through JSON.
  """
  @spec build_result_and_model(map(), map()) :: {struct(), struct() | nil}
  def build_result_and_model(state, reduce_op) do
    {message, [model | _]} = build_result_and_models(state, reduce_op)
    {message, model}
  end

  @doc """
  Builds the result for a delivery and returns the final read model of each partition, in the
  order of the delivery's partitions.
  """
  @spec build_result_and_models(map(), map()) :: {struct(), [struct() | nil]}
  def build_result_and_models(state, reduce_op) do
    partitions = PageMessages.partitions_of(reduce_op)

    context =
      BatchContext.for_message(reduce_op,
        observer_id: state.module.__chronicle_reducer__(:id),
        event_store: Map.get(state, :event_store, ""),
        namespace: Map.get(state, :namespace, ""),
        event_sequence_id: "event-log"
      )

    reduced = reduce_partitions(state, partitions, context)
    outcomes = Enum.map(reduced, &elem(&1, 0))
    models = Enum.map(reduced, &elem(&1, 1))
    {encode_result(reduce_op, outcomes), models}
  end

  @doc """
  Builds a failed `ReducerMessage` result for a delivery that is answered without being
  handled, because the kernel has already stopped waiting for it.
  """
  @spec expired_result(map(), String.t()) :: struct()
  def expired_result(reduce_op, reason) do
    outcomes =
      reduce_op
      |> PageMessages.partitions_of()
      |> Enum.map(fn partition ->
        %{PartitionSettlement.outcome(partition.partition, :failed, 0) | messages: [reason]}
      end)

    encode_result(reduce_op, outcomes)
  end

  # A single partition is reduced in this process, so process-local context (Logger metadata,
  # the current identity) reaches reduce/3 as before pages existed.
  defp reduce_partitions(state, [partition], context),
    do: [reduce_partition(state, partition, context)]

  defp reduce_partitions(state, partitions, context) do
    max_concurrency = Map.get(state, :max_concurrency) || System.schedulers_online()

    partitions
    |> Task.async_stream(&reduce_partition(state, &1, context),
      max_concurrency: max_concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.zip(partitions)
    |> Enum.map(fn
      {{:ok, reduced}, _partition} ->
        reduced

      {{:exit, reason}, partition} ->
        {%{
           PartitionSettlement.outcome(partition.partition, :failed, 0)
           | messages: [inspect(reason)],
             stack_trace: inspect(reason)
         }, nil}
    end)
  end

  defp reduce_partition(state, partition, context) do
    initial_model = decode_model(state.model_module, partition.initial_state)

    {outcome, model} =
      case Map.get(state, :batch_functions, []) do
        [] ->
          fold(state, partition, initial_model)

        [{name, observed}] ->
          reduce_batch(state, partition, initial_model, name, observed, context)
      end

    {with_read_model(outcome, model), model}
  end

  defp fold(state, partition, initial_model) do
    {final_model, problem} =
      Enum.reduce_while(partition.events, {initial_model, nil}, fn event, {model, nil} ->
        case apply_reduce(state, event, model) do
          {:ok, new_model} ->
            {:cont, {new_model, nil}}

          {:error, reason} ->
            at = PageMessages.sequence_number(event)
            {:halt, {model, PartitionSettlement.failed(partition.partition, at, reason)}}
        end
      end)

    sequence_numbers = Enum.map(partition.events, &PageMessages.sequence_number/1)

    {PartitionSettlement.settle(partition.partition, sequence_numbers, List.wrap(problem)),
     final_model}
  end

  defp reduce_batch(state, partition, initial_model, name, observed, context) do
    reducer_id = state.module.__chronicle_reducer__(:id)

    case decode_batch(state, partition, observed) do
      {:error, at, reason} ->
        {PartitionSettlement.settle(partition.partition, [], [
           PartitionSettlement.failed(partition.partition, at, reason)
         ]), initial_model}

      {:ok, []} ->
        sequence_numbers = Enum.map(partition.events, &PageMessages.sequence_number/1)
        {PartitionSettlement.settle(partition.partition, sequence_numbers, []), initial_model}

      {:ok, entries} ->
        batch = EventBatch.new(entries, context.can_defer?)

        result =
          Tracing.with_telemetry_span(
            [:cratis, :chronicle, :client, :reducer, :reduce_batch],
            %{reducer_id: reducer_id, function: name, event_count: EventBatch.count(batch)},
            "cratis.chronicle.client.reducer.reduce_batch",
            %{
              "cratis.event_sequence.id" => "event-log",
              "cratis.observer.id" => reducer_id,
              kind: :consumer
            },
            fn ->
              try do
                {:reduced, apply(state.module, name, [batch, initial_model, context])}
              rescue
                e -> {:error, e}
              end
            end
          )

        batch_result(state, name, partition, entries, initial_model, context, result)
    end
  end

  defp batch_result(
         _state,
         _name,
         partition,
         _entries,
         initial_model,
         _context,
         {:reduced, %EventBatch{} = batch}
       ) do
    case EventBatch.outcomes(batch) do
      [] ->
        failed(partition, initial_model, @batch_return_shape)

      outcomes ->
        earliest = Enum.min_by(outcomes, & &1.at)
        settled(partition, PartitionSettlement.from_batch_outcome(earliest), initial_model)
    end
  end

  defp batch_result(
         _state,
         _name,
         partition,
         entries,
         _initial_model,
         _context,
         {:reduced, model}
       )
       when is_map(model) or is_nil(model) do
    {_partition, _event, ctx} = List.last(entries)
    {PartitionSettlement.outcome(partition.partition, :success, ctx.sequence_number), model}
  end

  defp batch_result(
         _state,
         _name,
         partition,
         entries,
         initial_model,
         context,
         {:reduced, {:defer, retry_after}}
       )
       when is_integer(retry_after) and retry_after >= 0 do
    {_partition, _event, first} = List.first(entries)

    problem =
      if context.can_defer? do
        PartitionSettlement.deferred(partition.partition, first.sequence_number, retry_after)
      else
        PartitionSettlement.failed(
          partition.partition,
          first.sequence_number,
          DeferralNotSupportedByKernel.exception(partition: partition.partition)
        )
      end

    settled(partition, problem, initial_model)
  end

  defp batch_result(
         _state,
         _name,
         partition,
         _entries,
         initial_model,
         _context,
         {:reduced, {:error, reason}}
       ),
       do: failed(partition, initial_model, reason)

  defp batch_result(
         _state,
         _name,
         partition,
         _entries,
         initial_model,
         _context,
         {:error, reason}
       ),
       do: failed(partition, initial_model, reason)

  defp batch_result(state, name, partition, _entries, initial_model, _context, {:reduced, other}) do
    failed(
      partition,
      initial_model,
      "#{inspect(state.module)}.#{name}/3 returned #{inspect(other)}; #{@batch_return_shape}"
    )
  end

  # A failed or deferred event source writes no state: nothing of it counts as handled.
  defp settled(partition, problem, initial_model),
    do: {PartitionSettlement.settle(partition.partition, [], [problem]), initial_model}

  defp failed(partition, initial_model, reason) do
    at =
      case partition.events do
        [first | _] -> PageMessages.sequence_number(first)
        [] -> 0
      end

    settled(partition, PartitionSettlement.failed(partition.partition, at, reason), initial_model)
  end

  # Decodes the partition's events of the types the batch function observes, in order.
  defp decode_batch(state, partition, observed) do
    observed_ids = MapSet.new(observed, & &1.__chronicle_event_type__(:id))

    partition.events
    |> Enum.filter(&MapSet.member?(observed_ids, PageMessages.event_type_id(&1)))
    |> Enum.reduce_while({:ok, []}, fn appended_event, {:ok, entries} ->
      module = Map.fetch!(state.event_type_map, PageMessages.event_type_id(appended_event))

      case decode_event(module, Map.get(appended_event, :Content, "")) do
        {:ok, event} ->
          ctx =
            build_context(Map.get(appended_event, :Context, %{}), event_sequence_id: "event-log")

          {:cont, {:ok, [{partition.partition, event, ctx} | entries]}}

        {:error, reason} ->
          {:halt, {:error, PageMessages.sequence_number(appended_event), {:decode, reason}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp with_read_model(%{state: :success} = outcome, model),
    do: guard_read_model_size(%{outcome | read_model_state: encode_model(model)})

  defp with_read_model(outcome, _model), do: outcome

  defp encode_model(nil), do: ""
  defp encode_model(model), do: Chronicle.Serialization.to_json(model, :identity)

  defp encode_result(reduce_op, outcomes) do
    delivery_id = Map.get(reduce_op, :DeliveryId, 0) || 0

    result =
      if PageMessages.paged?(reduce_op) do
        struct(ReducerResult,
          DeliveryId: delivery_id,
          Partitions:
            Enum.map(outcomes, &PartitionSettlement.partition_result(PartitionResult, &1))
        )
      else
        [outcome] = outcomes

        struct(ReducerResult,
          Partition: outcome.partition,
          State: PartitionSettlement.legacy_state(outcome),
          LastSuccessfulObservation: outcome.last_successful_observation,
          ExceptionMessages: outcome.messages,
          ExceptionStackTrace: outcome.stack_trace,
          ReadModelState: outcome.read_model_state,
          # Echoed so the kernel completes exactly this delivery, not just the oldest one
          # pending for the partition.
          DeliveryId: delivery_id
        )
      end

    struct(ReducerMessage, Content: struct(OneOf, Value1: result))
  end

  # A read model larger than the message limit makes the kernel answer ResourceExhausted, and the
  # failed exchange can break the connection every observer shares. Report the reduction as failed
  # instead (the partition then shows up as a failed partition with a clear reason).
  defp guard_read_model_size(outcome) do
    case Chronicle.PayloadLimit.check(outcome.read_model_state) do
      :ok ->
        outcome

      {:error, {:payload_too_large, size, limit}} ->
        message =
          "Read model state is #{size} bytes, which exceeds the #{limit} byte message limit. " <>
            "Split it into smaller read models (for example one per child) or raise :max_payload_bytes."

        %{outcome | state: :failed, read_model_state: "", messages: [message | outcome.messages]}
    end
  end

  defp apply_reduce(state, appended_event, model) do
    context = Map.get(appended_event, :Context, %{})
    event_type = Map.get(context, :EventType, %{})
    event_type_id = Map.get(event_type, :Id, "")

    case Map.get(state.event_type_map, event_type_id) do
      nil ->
        {:ok, model}

      event_module ->
        ctx = build_context(context, event_sequence_id: "event-log")
        content = Map.get(appended_event, :Content, "")

        case decode_event(event_module, content) do
          {:ok, event} ->
            Tracing.with_telemetry_span(
              [:cratis, :chronicle, :client, :reducer, :reduce],
              %{
                reducer_id: state.module.__chronicle_reducer__(:id),
                event_type_id: event_type_id
              },
              "cratis.chronicle.client.reducer.reduce",
              %{
                "cratis.event_sequence.id" => "event-log",
                "cratis.event_type.id" => event_type_id,
                "cratis.observer.id" => state.module.__chronicle_reducer__(:id),
                "cratis.correlation_id" => ctx.correlation_id,
                kind: :consumer
              },
              fn ->
                try do
                  middleware = Chronicle.Middleware.for_module(state.module, :reducer)

                  {:ok,
                   Chronicle.Middleware.run(middleware, event, ctx, fn event, ctx ->
                     state.module.reduce(event, model, ctx)
                   end)}
                rescue
                  e -> {:error, e}
                end
              end
            )

          {:error, reason} ->
            Logger.warning("Failed to decode event #{event_type_id}: #{inspect(reason)}")
            {:ok, model}
        end
    end
  end

  defp decode_model(_module, ""), do: nil
  defp decode_model(_module, nil), do: nil

  defp decode_model(module, json) do
    Chronicle.Serialization.decode(module, json, :identity)
  rescue
    _ -> nil
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

  @doc false
  def build_context(ctx, opts \\ []), do: Chronicle.Events.EventContext.from_wire(ctx, opts)
end
