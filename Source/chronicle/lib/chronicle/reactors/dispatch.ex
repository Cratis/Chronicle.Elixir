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

  alias Cratis.Chronicle.Contracts.Observation.Reactors.{ReactorMessage, ReactorResult}

  alias Cratis.Chronicle.Contracts.Observation.Reactors.OneOf_RegisterReactor_ReactorResult,
    as: OneOf

  @doc """
  Builds the `ReactorMessage` result for one batch of observed events, dispatching each
  through the reactor module's handler and appending any side effect it returns.
  """
  @spec build_result(map(), map()) :: struct()
  def build_result(state, events_to_observe) do
    partition = Map.get(events_to_observe, :Partition, "")
    events = Map.get(events_to_observe, :Events, [])

    {observation_state, exception_messages, stack_trace} =
      Enum.reduce_while(events, {:success, [], ""}, fn appended_event, _acc ->
        case dispatch_event(state, appended_event) do
          :ok -> {:cont, {:success, [], ""}}
          {:error, reason} -> {:halt, {:failed, [inspect(reason)], format_stack_trace(reason)}}
        end
      end)

    last_seq =
      case List.last(events) do
        nil -> 0
        event -> Map.get(Map.get(event, :Context, %{}), :SequenceNumber, 0)
      end

    struct(ReactorMessage,
      Content:
        struct(OneOf,
          Value1:
            struct(ReactorResult,
              Partition: partition,
              State: encode_observation_state(observation_state),
              LastSuccessfulObservation: last_seq,
              ExceptionMessages: exception_messages,
              ExceptionStackTrace: stack_trace,
              # Echoed so the kernel completes exactly this delivery, not just the oldest one
              # pending for the partition.
              DeliveryId: Map.get(events_to_observe, :DeliveryId, 0) || 0
            )
        )
    )
  end

  @doc """
  Builds a failed `ReactorMessage` result for a batch that is answered without being
  handled, because the kernel has already stopped waiting for it.
  """
  @spec expired_result(map(), String.t()) :: struct()
  def expired_result(events_to_observe, reason) do
    struct(ReactorMessage,
      Content:
        struct(OneOf,
          Value1:
            struct(ReactorResult,
              Partition: Map.get(events_to_observe, :Partition, ""),
              State: encode_observation_state(:failed),
              LastSuccessfulObservation: 0,
              ExceptionMessages: [reason],
              ExceptionStackTrace: "",
              DeliveryId: Map.get(events_to_observe, :DeliveryId, 0) || 0
            )
        )
    )
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

  # ObservationState enum: Success = 1, Failed = 2
  defp encode_observation_state(:success), do: 1
  defp encode_observation_state(:failed), do: 2

  defp format_stack_trace(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_stack_trace(reason), do: inspect(reason)
end
