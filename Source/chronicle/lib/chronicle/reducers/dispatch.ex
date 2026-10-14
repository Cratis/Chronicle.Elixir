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

  alias Cratis.Chronicle.Contracts.Observation.Reducers.{ReducerMessage, ReducerResult}

  alias Cratis.Chronicle.Contracts.Observation.Reducers.OneOf_RegisterReducer_ReducerResult,
    as: OneOf

  @doc """
  Builds the `ReducerMessage` result for one reduce operation, applying the reducer
  module's `reduce/3` to each event in turn and encoding the resulting read model state.
  """
  @spec build_result(map(), map()) :: struct()
  def build_result(state, reduce_op) do
    {message, _final_model} = build_result_and_model(state, reduce_op)
    message
  end

  @doc """
  Same as `build_result/2`, but also returns the final (decoded) read model struct —
  used by `Chronicle.Testing` to keep in-memory reducer state without a round trip
  through JSON.
  """
  @spec build_result_and_model(map(), map()) :: {struct(), struct() | nil}
  def build_result_and_model(state, reduce_op) do
    partition = Map.get(reduce_op, :Partition, "")
    initial_state_json = Map.get(reduce_op, :InitialState, "")
    events = Map.get(reduce_op, :Events, [])

    initial_model = decode_model(state.model_module, initial_state_json)

    {final_state, observation_state, exception_messages, stack_trace} =
      Enum.reduce_while(events, {initial_model, :success, [], ""}, fn event, {model, _, _, _} ->
        case apply_reduce(state, event, model) do
          {:ok, new_model} ->
            {:cont, {new_model, :success, [], ""}}

          {:error, reason} ->
            {:halt, {model, :failed, [inspect(reason)], format_stack_trace(reason)}}
        end
      end)

    last_seq =
      case List.last(events) do
        nil -> 0
        event -> Map.get(Map.get(event, :Context, %{}), :SequenceNumber, 0)
      end

    read_model_json =
      case final_state do
        nil -> ""
        model -> Chronicle.Serialization.to_json(model, :identity)
      end

    {read_model_json, observation_state, exception_messages, stack_trace} =
      guard_read_model_size(read_model_json, observation_state, exception_messages, stack_trace)

    message =
      struct(ReducerMessage,
        Content:
          struct(OneOf,
            Value1:
              struct(ReducerResult,
                Partition: partition,
                State: encode_observation_state(observation_state),
                LastSuccessfulObservation: last_seq,
                ExceptionMessages: exception_messages,
                ExceptionStackTrace: stack_trace,
                ReadModelState: read_model_json
              )
          )
      )

    {message, final_state}
  end

  # A read model larger than the message limit makes the kernel answer ResourceExhausted, and the
  # failed exchange can break the connection every observer shares. Report the reduction as failed
  # instead (the partition then shows up as a failed partition with a clear reason).
  defp guard_read_model_size(json, observation_state, messages, stack_trace) do
    case Chronicle.PayloadLimit.check(json) do
      :ok ->
        {json, observation_state, messages, stack_trace}

      {:error, {:payload_too_large, size, limit}} ->
        message =
          "Read model state is #{size} bytes, which exceeds the #{limit} byte message limit. " <>
            "Split it into smaller read models (for example one per child) or raise :max_payload_bytes."

        {"", :failed, [message | messages], stack_trace}
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

  # ObservationState enum: Success = 1, Failed = 2
  defp encode_observation_state(:success), do: 1
  defp encode_observation_state(:failed), do: 2

  defp format_stack_trace(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_stack_trace(reason), do: inspect(reason)
end
