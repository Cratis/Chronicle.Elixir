# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.Streams do
  @moduledoc """
  Closing, reopening and inspecting event streams, and reading event metadata.

  Closing a stream scope stops further events being appended inside it. A scope is described by
  any of `:event_source_id`, `:event_source_type`, `:event_stream_type` and `:event_stream_id`
  (leave a dimension out to leave it unconstrained). Closing events declared with
  `Chronicle.Events.EventType.closes_stream/1` close scopes as part of their own append; the
  functions here are the operator's tools for the same ends and for looking at the result.

  Mirrors the .NET client's closed-stream APIs. All functions accept `:client`, `:namespace`
  and `:event_sequence_id` (default `"event-log"`).
  """

  alias Chronicle.Connections.Connection
  alias Chronicle.EventSequences.{EventLog, PreparedEvent, ResolvedIdentity}
  alias Chronicle.Events.EventType
  alias Chronicle.WireResult

  @max_sequence_numbers 500

  alias Cratis.Chronicle.Contracts.Sequences.{
    ClosedStreamsRequest,
    CompleteStreamScopeRequest,
    EventSequences,
    IsStreamScopeCompletedRequest,
    MetadataAtRequest,
    ReopenStreamScopeRequest,
    VerifyContentRequest
  }

  defmodule ClosedStream do
    @moduledoc """
    A closed stream scope: which scope it is, how it was closed (`:complete_stream` for an
    operator's call, `:closing_event` for a closing event), by whom, and when.
    """
    defstruct [
      :event_source_id,
      :event_source_type,
      :event_stream_type,
      :event_stream_id,
      :origin,
      :closed_by,
      :sequence_number,
      :closed_at
    ]

    @type t :: %__MODULE__{}
  end

  @doc """
  Lists the closed stream scopes, optionally narrowed by `:event_source_id`,
  `:event_source_type`, `:event_stream_type` and `:event_stream_id`.
  """
  @spec closed(keyword()) :: {:ok, [ClosedStream.t()]} | {:error, term()}
  def closed(opts \\ []) do
    with {:ok, channel, config, namespace, sequence} <- context(opts) do
      request =
        struct(ClosedStreamsRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: sequence,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, "")
        )

      with {:ok, envelope} <- EventSequences.Stub.closed_streams(channel, request),
           {:ok, data} <- WireResult.unwrap(envelope) do
        {:ok, Enum.map(data, &decode_closed_stream/1)}
      end
    end
  end

  @doc """
  Closes a stream scope so no further events can be appended inside it.

  The scope is described with `:event_source_id`, `:event_source_type`, `:event_stream_type` and
  `:event_stream_id`. Pass `:expected_tail_sequence_number` to refuse the closure when the scope's
  tail moved since it was read.

  Returns `{:ok, sequence_number}` or `{:error, reason}` where reason is one of
  `:already_completed`, `:default_stream_cannot_be_completed`, `:empty_scope` or
  `:expected_tail_mismatch`.
  """
  @spec complete_scope(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def complete_scope(opts) do
    with {:ok, channel, config, namespace, sequence} <- context(opts) do
      request =
        struct(CompleteStreamScopeRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: sequence,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, ""),
          ExpectedTailSequenceNumber:
            Keyword.get(opts, :expected_tail_sequence_number, 18_446_744_073_709_551_615)
        )

      with {:ok, envelope} <- EventSequences.Stub.complete_stream_scope(channel, request),
           {:ok, response} <- WireResult.unwrap(envelope) do
        EventLog.decode_complete_stream_response(response)
      end
    end
  end

  @doc """
  Reopens a stream scope that was closed with `complete_scope/1` (or `EventLog.complete_stream/3`).

  A scope closed by a closing event is reopened by appending one of its `reopened_by` events
  instead (`{:error, :closed_by_event}`). `reason` is recorded with the reopening. Returns `:ok`
  or `{:error, :not_completed | :closed_by_event | term}`.
  """
  @spec reopen_scope(String.t(), keyword()) :: :ok | {:error, term()}
  def reopen_scope(reason, opts) when is_binary(reason) do
    with {:ok, channel, config, namespace, sequence} <- context(opts) do
      request =
        struct(ReopenStreamScopeRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: sequence,
          Reason: reason,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, "")
        )

      with {:ok, envelope} <- EventSequences.Stub.reopen_stream_scope(channel, request),
           {:ok, response} <- WireResult.unwrap(envelope) do
        decode_reopen(response)
      end
    end
  end

  @doc "Whether the described stream scope is currently closed."
  @spec scope_completed?(keyword()) :: {:ok, boolean()} | {:error, term()}
  def scope_completed?(opts) do
    with {:ok, channel, config, namespace, sequence} <- context(opts) do
      request =
        struct(IsStreamScopeCompletedRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: sequence,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, "")
        )

      with {:ok, envelope} <- EventSequences.Stub.is_stream_scope_completed(channel, request),
           {:ok, response} <- WireResult.unwrap(envelope) do
        {:ok, Map.get(response, :IsCompleted, false)}
      end
    end
  end

  @doc """
  Reads the metadata of events by sequence number: who caused them, when, under which
  correlation id, their tags and subject - without their content.

  Returns `{:ok, [metadata]}` where each entry is a map with `:sequence_number`, `:event_type_id`,
  `:event_source_type`, `:event_source_id`, `:event_stream_type`, `:event_stream_id`, `:occurred`,
  `:correlation_id`, `:causation`, `:caused_by` (gains `:on_behalf_of`), `:initiator_type`
  (`:unknown | :user | :agent | :system`), `:resolved_caused_by` (a
  `Chronicle.EventSequences.ResolvedIdentity`, carrying how the kernel resolved the identity),
  `:tags`, `:subject` and `:event_source`.

  `sequence_numbers` is de-duplicated before the request is sent. The kernel limits a single
  request to #{@max_sequence_numbers} locators; above that this returns
  `{:error, {:too_many_event_locators, #{@max_sequence_numbers}}}` without sending one.
  """
  @spec get_metadata([non_neg_integer()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_metadata(sequence_numbers, opts \\ []) when is_list(sequence_numbers) do
    deduped = Enum.uniq(sequence_numbers)

    if length(deduped) > @max_sequence_numbers do
      {:error, {:too_many_event_locators, @max_sequence_numbers}}
    else
      with {:ok, channel, config, namespace, sequence} <- context(opts) do
        request =
          struct(MetadataAtRequest,
            EventStore: config.event_store,
            Namespace: namespace,
            EventSequenceId: sequence,
            SequenceNumbers: deduped
          )

        with {:ok, envelope} <- EventSequences.Stub.metadata_at(channel, request),
             {:ok, data} <- WireResult.unwrap(envelope) do
          {:ok, Enum.map(data, &decode_metadata/1)}
        end
      end
    end
  end

  @doc """
  Reads the metadata of a single event by sequence number. See `get_metadata/2`.

  Returns `{:ok, metadata}`, `{:error, :not_found}` when no event exists at that sequence
  number, or `{:error, reason}`.
  """
  @spec get_metadata_at(non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_metadata_at(sequence_number, opts \\ []) when is_integer(sequence_number) do
    case get_metadata([sequence_number], opts) do
      {:ok, [metadata]} -> {:ok, metadata}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies that `event` is what was stored at `sequence_number`, by comparing content. Accepts
  either an event struct or a `Chronicle.EventSequences.PreparedEvent` from `EventLog.prepare/2`
  (verifying against the content it already captured, without re-serializing).

  Returns `{:ok, :equal | :different | :unavailable}`; `:unavailable` means the kernel could not
  compare (for example the content was redacted). Returns `{:error, {:unknown_event_type, module}}`
  when `event` does not `use Chronicle.Events.EventType`.
  """
  @spec verify_content(non_neg_integer(), struct() | PreparedEvent.t(), keyword()) ::
          {:ok, :equal | :different | :unavailable} | {:error, term()}
  def verify_content(sequence_number, event_or_prepared, opts \\ [])

  def verify_content(sequence_number, %PreparedEvent{} = prepared_event, opts) do
    send_verify_content(sequence_number, prepared_event.event_type, prepared_event.content, opts)
  end

  def verify_content(sequence_number, %module{} = event, opts) do
    if EventType.event_type?(module) do
      event_type =
        struct(Cratis.Chronicle.Contracts.Sequences.EventType,
          Id: module.__chronicle_event_type__(:id),
          Generation: module.__chronicle_event_type__(:generation)
        )

      send_verify_content(
        sequence_number,
        event_type,
        Chronicle.Serialization.to_json(event, :camel),
        opts
      )
    else
      {:error, {:unknown_event_type, module}}
    end
  end

  defp send_verify_content(sequence_number, event_type, content, opts) do
    with {:ok, channel, config, namespace, sequence} <- context(opts) do
      request =
        struct(VerifyContentRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: sequence,
          SequenceNumber: sequence_number,
          EventType: event_type,
          Content: content,
          EventSourceId: Keyword.get(opts, :event_source_id, "")
        )

      with {:ok, envelope} <- EventSequences.Stub.verify_content(channel, request),
           {:ok, response} <- WireResult.unwrap(envelope) do
        {:ok, decode_verification(Map.get(response, :Result))}
      end
    end
  end

  @doc false
  def decode_verification(result) when result in [:Equal, 1], do: :equal
  def decode_verification(result) when result in [:Different, 2], do: :different
  def decode_verification(_), do: :unavailable

  @doc false
  def decode_reopen(response) do
    if Map.get(response, :IsSuccess, false) do
      :ok
    else
      case Map.get(response, :Error) do
        error when error in [:NotCompleted, 1] -> {:error, :not_completed}
        error when error in [:ClosedByEvent, 2] -> {:error, :closed_by_event}
        other -> {:error, other}
      end
    end
  end

  @doc false
  def decode_closed_stream(stream) do
    %ClosedStream{
      event_source_id: Map.get(stream, :EventSourceId, ""),
      event_source_type: Map.get(stream, :EventSourceType, ""),
      event_stream_type: Map.get(stream, :EventStreamType, ""),
      event_stream_id: Map.get(stream, :EventStreamId, ""),
      origin: decode_origin(Map.get(stream, :Origin)),
      closed_by: Map.get(stream, :ClosedBy, ""),
      sequence_number: Map.get(stream, :SequenceNumber, 0),
      closed_at: offset(Map.get(stream, :ClosedAt))
    }
  end

  defp decode_origin(origin) when origin in [:ClosingEvent, 1], do: :closing_event
  defp decode_origin(_), do: :complete_stream

  @doc false
  def decode_metadata(metadata) do
    context =
      Chronicle.Events.EventContext.from_wire(%{
        CorrelationId: Map.get(metadata, :CorrelationId),
        Causation: Map.get(metadata, :Causation, [])
      })

    %{
      sequence_number: Map.get(metadata, :SequenceNumber, 0),
      event_type_id: Map.get(metadata, :EventTypeId, ""),
      event_source_type: Map.get(metadata, :EventSourceType, ""),
      event_source_id: Map.get(metadata, :EventSourceId, ""),
      event_stream_type: Map.get(metadata, :EventStreamType, ""),
      event_stream_id: Map.get(metadata, :EventStreamId, ""),
      occurred: offset(Map.get(metadata, :Occurred)),
      correlation_id: context.correlation_id,
      causation: context.causation,
      caused_by: identity_from_resolved(Map.get(metadata, :CausedBy)),
      initiator_type: initiator_type(Map.get(metadata, :InitiatorType)),
      resolved_caused_by: resolved_identity(Map.get(metadata, :CausedBy)),
      tags: Map.get(metadata, :Tags, []),
      subject: Map.get(metadata, :Subject, ""),
      event_source: Map.get(metadata, :EventSourceName)
    }
  end

  defp initiator_type(type) when type in [:User, 1], do: :user
  defp initiator_type(type) when type in [:Agent, 2], do: :agent
  defp initiator_type(type) when type in [:INITIATOR_TYPE_System, 3], do: :system
  defp initiator_type(_), do: :unknown

  # `Chronicle.Identity` is what an append declared: subject, name, user name and the
  # on-behalf-of chain, ignoring how the kernel resolved it.
  defp identity_from_resolved(nil), do: nil

  defp identity_from_resolved(resolved) do
    Chronicle.Identity.new(
      Map.get(resolved, :Subject, ""),
      Map.get(resolved, :Name, ""),
      Map.get(resolved, :UserName, ""),
      identity_from_resolved(Map.get(resolved, :OnBehalfOf))
    )
  end

  # `Chronicle.EventSequences.ResolvedIdentity` additionally carries how the kernel resolved it.
  defp resolved_identity(nil), do: nil

  defp resolved_identity(resolved) do
    %ResolvedIdentity{
      subject: Map.get(resolved, :Subject, ""),
      name: Map.get(resolved, :Name, ""),
      user_name: Map.get(resolved, :UserName, ""),
      resolution: identity_resolution(Map.get(resolved, :Resolution)),
      on_behalf_of: resolved_identity(Map.get(resolved, :OnBehalfOf))
    }
  end

  defp identity_resolution(resolution) when resolution in [:Resolved, 0], do: :resolved

  defp identity_resolution(resolution) when resolution in [:NameUnavailable, 1],
    do: :name_unavailable

  defp identity_resolution(resolution) when resolution in [:Missing, 2], do: :missing

  defp identity_resolution(resolution) when resolution in [:IDENTITY_RESOLUTION_System, 4],
    do: :system

  defp identity_resolution(_), do: :not_set

  defp offset(%{Value: value}), do: value
  defp offset(_), do: nil

  defp context(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        with {:ok, channel} <- Connection.channel(config.connection) do
          {:ok, channel, config, Keyword.get(opts, :namespace) || config.namespace,
           Keyword.get(opts, :event_sequence_id, "event-log")}
        end

      _ ->
        {:error, :no_client}
    end
  end
end
