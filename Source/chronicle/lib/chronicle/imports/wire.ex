# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.Wire do
  @moduledoc false

  # Converts between the client's import types and the generated `Imports` contracts.

  alias Bcl.Guid, as: BclGuid
  alias Chronicle.Auditing.{CausationEntry, CausationType}
  alias Chronicle.Correlation.CorrelationId
  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Events.EventType, as: ClientEventType
  alias Chronicle.Imports.{ImportProgress, ImportRejection, ImportResult}

  alias Cratis.Chronicle.Contracts.Imports.{
    Causation,
    EventType,
    Identity,
    ImportEvent,
    NamedTag,
    SerializableDateTimeOffset
  }

  @unavailable_sequence_number 18_446_744_073_709_551_615

  # In wire order: the enum's numbers are the positions in this list.
  @ordered_states [
    Open: :open,
    Staging: :staging,
    Validating: :validating,
    Committing: :committing,
    Completed: :completed,
    Failed: :failed,
    Abandoned: :abandoned
  ]
  @states Map.new(@ordered_states)
  @state_numbers @ordered_states
                 |> Enum.with_index()
                 |> Map.new(fn {{_, state}, number} -> {number, state} end)

  @spec to_import_event(EventForEventSourceId.t()) :: {:ok, struct()} | {:error, term()}
  def to_import_event(%EventForEventSourceId{event: %module{} = event} = entry) do
    if ClientEventType.event_type?(module) do
      {:ok,
       %ImportEvent{
         EventSourceId: entry.event_source_id,
         EventSourceType: entry.event_source_type || "",
         EventStreamType: entry.event_stream_type || "",
         EventStreamId: entry.event_stream_id || "",
         EventType: event_type(entry),
         Content: content(entry),
         Tags: Enum.uniq((entry.tags || []) ++ ClientEventType.declared_tags(event)),
         NamedTags: Enum.map(entry.named_tags || %{}, fn {k, v} -> named_tag(k, v) end),
         Occurred: occurred(entry.occurred),
         Subject: subject(entry, event),
         CorrelationId: correlation_id(entry.correlation_id),
         Causation: Enum.map(entry.causation || [], &causation/1),
         CausedBy: identity(entry.identity),
         IdempotencyKey: entry.idempotency_key || "",
         EventSource: event_source(entry),
         SourceSequenceNumber: entry.source_sequence_number || 0
       }}
    else
      {:error, {:unknown_event_type, module}}
    end
  end

  # Measures an event the way the kernel counts it against its chunk byte limit: the
  # content, tags, named tags, causation and idempotency key, as UTF-8.
  @spec size_of(struct()) :: non_neg_integer()
  def size_of(%ImportEvent{} = event) do
    tags = Enum.reduce(event."Tags", 0, &(byte_size(&1) + &2))

    named =
      Enum.reduce(event."NamedTags", 0, &(byte_size(&1."Name") + byte_size(&1."Value") + &2))

    causation =
      Enum.reduce(event."Causation", 0, fn c, acc ->
        Enum.reduce(c."Properties" || %{}, acc + byte_size(c."Type"), fn {k, v}, sum ->
          sum + byte_size(k) + byte_size(v)
        end)
      end)

    byte_size(event."Content") + byte_size(event."IdempotencyKey") + tags + named + causation
  end

  @spec result(map(), String.t()) :: ImportResult.t()
  def result(progress, import_id) do
    committed = Map.get(progress, :EventsCommitted, 0)

    %ImportResult{
      import_id: guid_to_string(Map.get(progress, :ImportId)) || import_id,
      state: state(Map.get(progress, :State)),
      events_staged: Map.get(progress, :EventsStaged, 0),
      events_committed: committed,
      already_appended: Map.get(progress, :AlreadyAppended, 0),
      first_sequence_number: sequence_number(committed, Map.get(progress, :FirstSequenceNumber)),
      last_sequence_number: sequence_number(committed, Map.get(progress, :LastSequenceNumber)),
      rejected_count: Map.get(progress, :RejectedCount, 0),
      rejections: Enum.map(Map.get(progress, :Rejections) || [], &rejection/1),
      failure_reason: blank_to_nil(Map.get(progress, :FailureReason))
    }
  end

  @spec progress(map(), String.t()) :: ImportProgress.t()
  def progress(progress, import_id) do
    %ImportProgress{
      import_id: guid_to_string(Map.get(progress, :ImportId)) || import_id,
      state: state(Map.get(progress, :State)),
      events_received: Map.get(progress, :EventsReceived, 0),
      events_staged: Map.get(progress, :EventsStaged, 0),
      events_committed: Map.get(progress, :EventsCommitted, 0),
      already_appended: Map.get(progress, :AlreadyAppended, 0),
      events_rejected: Map.get(progress, :RejectedCount, 0),
      chunks_acknowledged: Map.get(progress, :AcknowledgedChunks, 0),
      events_acknowledged: Map.get(progress, :AcknowledgedEvents, 0)
    }
  end

  @spec rejection(map()) :: ImportRejection.t()
  def rejection(rejection) do
    %ImportRejection{
      index: Map.get(rejection, :Index, 0),
      event_type: Map.get(rejection, :EventType, ""),
      reasons: Map.get(rejection, :Reasons) || []
    }
  end

  @spec state(atom() | integer() | nil) :: ImportResult.state()
  def state(state) when is_atom(state), do: Map.get(@states, state, :open)
  def state(state) when is_integer(state), do: Map.get(@state_numbers, state, :open)

  @spec on_invalid(:reject | :skip) :: atom()
  def on_invalid(:skip), do: :Skip
  def on_invalid(_), do: :Reject

  @spec on_invalid_from_wire(atom() | integer()) :: :reject | :skip
  def on_invalid_from_wire(value) when value in [:Skip, 1], do: :skip
  def on_invalid_from_wire(_), do: :reject

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(value) when value in [nil, ""], do: nil
  def blank_to_nil(value), do: value

  @spec guid(String.t() | nil) :: struct() | nil
  def guid(nil), do: nil

  def guid(value) when is_binary(value) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = String.replace(value, "-", "")

    # protobuf-net carries Guid.ToByteArray() in two little-endian words.
    bytes =
      reverse(Base.decode16!(a, case: :mixed)) <>
        reverse(Base.decode16!(b, case: :mixed)) <>
        reverse(Base.decode16!(c, case: :mixed)) <> Base.decode16!(d <> e, case: :mixed)

    <<lo::little-unsigned-64, hi::little-unsigned-64>> = bytes
    %BclGuid{lo: lo, hi: hi}
  end

  @spec guid_to_string(struct() | nil) :: String.t() | nil
  def guid_to_string(%{lo: lo, hi: hi}) when is_integer(lo) and is_integer(hi) do
    <<a::little-32, b::little-16, c::little-16, rest::binary-size(8)>> =
      <<lo::little-unsigned-64, hi::little-unsigned-64>>

    <<a::32, b::16, c::16, rest::binary>>
    |> Base.encode16(case: :lower)
    |> then(fn <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> ->
      Enum.join([p1, p2, p3, p4, p5], "-")
    end)
  end

  def guid_to_string(_), do: nil

  defp event_type(%EventForEventSourceId{prepared: %{event_type: prepared}, generation: g}),
    do: %EventType{Id: Map.get(prepared, :Id), Generation: g || Map.get(prepared, :Generation)}

  defp event_type(%EventForEventSourceId{event: %module{}, generation: generation}) do
    %EventType{
      Id: module.__chronicle_event_type__(:id),
      Generation: generation || module.__chronicle_event_type__(:generation)
    }
  end

  defp content(%EventForEventSourceId{prepared: %{content: content}}), do: content
  defp content(%EventForEventSourceId{event: event}), do: Chronicle.Serialization.to_json(event)

  defp subject(%EventForEventSourceId{subject: subject}, event) when subject in [nil, ""],
    do: ClientEventType.declared_subject(event) || ""

  defp subject(%EventForEventSourceId{subject: subject}, _event), do: subject

  defp event_source(%EventForEventSourceId{routing: nil}), do: ""

  defp event_source(%EventForEventSourceId{routing: routing}),
    do: Chronicle.EventSources.Routing.event_source(routing)

  defp named_tag(name, value), do: %NamedTag{Name: to_string(name), Value: to_string(value)}

  defp occurred(nil), do: nil
  defp occurred(%DateTime{} = at), do: %SerializableDateTimeOffset{Value: DateTime.to_iso8601(at)}

  defp correlation_id(nil), do: nil
  defp correlation_id(%CorrelationId{value: value}), do: guid(value)
  defp correlation_id(value) when is_binary(value), do: guid(value)

  defp causation(%CausationEntry{type: %CausationType{value: type}} = entry) do
    %Causation{
      Type: type,
      Occurred: occurred(entry.occurred),
      Properties: Map.new(entry.properties, fn {k, v} -> {to_string(k), to_string(v)} end)
    }
  end

  defp identity(nil), do: nil

  defp identity(identity) do
    %Identity{
      Subject: identity.subject || "",
      Name: identity.name || "",
      UserName: identity.user_name || "",
      OnBehalfOf: identity(identity.on_behalf_of)
    }
  end

  defp sequence_number(0, _), do: nil
  defp sequence_number(_, @unavailable_sequence_number), do: nil
  defp sequence_number(_, value), do: value

  defp reverse(binary),
    do: binary |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
end
