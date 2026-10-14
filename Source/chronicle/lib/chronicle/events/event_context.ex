# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventContext do
  @moduledoc """
  The context of an event handed to reactors and reducers.

  It carries the same information as the .NET client's `EventContext`, so a handler can see
  who caused an event, how it is correlated and where it sits in the event sequence.

  A struct is a map: handlers can keep pattern matching on keys
  (`def handle(event, %{event_source_id: id})`) or use `context.caused_by`.

    * `:event_type` — `%{id: String.t(), generation: non_neg_integer()}`
    * `:event_source_type`, `:event_source_id`, `:event_source` (the registered event source
      name, or `nil`), `:event_stream_type`, `:event_stream_id`
    * `:sequence_number`, `:occurred`
    * `:event_store`, `:namespace`, `:event_sequence_id` (when known)
    * `:correlation_id` — string
    * `:caused_by` — `Chronicle.Identity` (including `on_behalf_of`), or `nil`
    * `:causation` — list of `Chronicle.Auditing.CausationEntry`
    * `:tags` — list of tag strings; `:named_tags` — map of name to value
    * `:hash`, `:subject`
    * `:appended_generation` — the generation that was actually appended, regardless of
      which generation the handler is written against. `0` means unknown: an older kernel
      that doesn't send this field, or an event appended outside a registered event source.
    * `:observation_state` — the observation state; `:replaying?` is `true` while the observer is replaying
    * `:delivery_id` — reactors only; see `delivery_id/1`
  """

  alias Chronicle.Auditing.{CausationEntry, CausationType}
  alias Chronicle.Identity

  defstruct event_type: nil,
            event_source_type: "",
            event_source_id: "",
            event_source: nil,
            event_stream_type: "",
            event_stream_id: "",
            sequence_number: 0,
            occurred: nil,
            event_store: "",
            namespace: "",
            event_sequence_id: nil,
            correlation_id: "",
            caused_by: nil,
            causation: [],
            tags: [],
            named_tags: %{},
            hash: "",
            subject: "",
            appended_generation: 0,
            observation_state: 0,
            replaying?: false,
            delivery_id: nil

  @type t :: %__MODULE__{}

  @doc """
  Builds an event context from the wire `EventContext` of a reactor or reducer observation.

  Options: `:event_sequence_id` and `:reactor_id` (when given, a `:delivery_id` is derived).
  """
  @spec from_wire(map(), keyword()) :: t()
  def from_wire(ctx, opts \\ []) when is_map(ctx) do
    occurred = Map.get(ctx, :Occurred)

    context = %__MODULE__{
      event_type: event_type(Map.get(ctx, :EventType)),
      event_source_type: Map.get(ctx, :EventSourceType, ""),
      event_source_id: Map.get(ctx, :EventSourceId, ""),
      event_source: non_empty(Map.get(ctx, :EventSource)),
      event_stream_type: Map.get(ctx, :EventStreamType, ""),
      event_stream_id: Map.get(ctx, :EventStreamId, ""),
      sequence_number: Map.get(ctx, :SequenceNumber, 0),
      occurred: occurred && Map.get(occurred, :Value),
      event_store: Map.get(ctx, :EventStore, ""),
      namespace: Map.get(ctx, :Namespace, ""),
      event_sequence_id: Keyword.get(opts, :event_sequence_id),
      correlation_id: guid_to_string(Map.get(ctx, :CorrelationId)),
      caused_by: identity(Map.get(ctx, :CausedBy)),
      causation: ctx |> Map.get(:Causation, []) |> Enum.map(&causation/1),
      tags: Map.get(ctx, :Tags, []),
      named_tags:
        ctx |> Map.get(:NamedTags, []) |> Map.new(&{Map.get(&1, :Name), Map.get(&1, :Value)}),
      hash: Map.get(ctx, :Hash, ""),
      subject: Map.get(ctx, :Subject, ""),
      appended_generation: Map.get(ctx, :AppendedGeneration, 0),
      observation_state: Map.get(ctx, :ObservationState, 0),
      replaying?: Map.get(ctx, :ObservationState, 0) in [:Replay, 2]
    }

    case Keyword.get(opts, :reactor_id) do
      nil -> context
      reactor_id -> %{context | delivery_id: delivery_id(context, reactor_id)}
    end
  end

  @doc """
  The stable identity of one delivery of an event to a reactor.

  Derived exactly like the .NET `ReactorDelivery.Id`: the reactor id, event store, namespace,
  event sequence id, event source id and sequence number joined with `#`. Use it as the key of
  whatever records that a side effect completed.
  """
  @spec delivery_id(t(), String.t()) :: String.t()
  def delivery_id(%__MODULE__{} = context, reactor_id) do
    [
      reactor_id,
      context.event_store,
      context.namespace,
      context.event_sequence_id,
      context.event_source_id,
      context.sequence_number
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("#")
  end

  defp non_empty(name) when is_binary(name) and name != "", do: name
  defp non_empty(_), do: nil

  defp event_type(nil), do: nil

  defp event_type(type),
    do: %{id: Map.get(type, :Id, ""), generation: Map.get(type, :Generation, 1)}

  defp identity(nil), do: nil

  defp identity(identity) do
    on_behalf_of =
      case Map.get(identity, :OnBehalfOf) do
        nil -> nil
        inner -> identity(inner)
      end

    Identity.new(
      Map.get(identity, :Subject, ""),
      Map.get(identity, :Name, ""),
      Map.get(identity, :UserName, ""),
      on_behalf_of
    )
  end

  defp causation(causation) do
    occurred =
      case Map.get(causation, :Occurred) do
        %{Value: value} -> value
        _ -> nil
      end

    %CausationEntry{
      occurred: occurred,
      type: CausationType.new(Map.get(causation, :Type, "")),
      properties: Map.get(causation, :Properties, %{}) |> Map.new()
    }
  end

  defp guid_to_string(%{lo: lo, hi: hi}) when is_integer(lo) and is_integer(hi) do
    <<a::little-32, b::little-16, c::little-16, d::binary-size(2), e::binary-size(6)>> =
      <<lo::little-unsigned-64, hi::little-unsigned-64>>

    [<<a::32>>, <<b::16>>, <<c::16>>, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  defp guid_to_string(value) when is_binary(value), do: value
  defp guid_to_string(_), do: ""
end
