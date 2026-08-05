# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EventSequence do
  @moduledoc """
  Represents a Chronicle event sequence.

  Use this module when you want to work with a non-default event sequence and keep
  the event sequence identifier close to the append/query operations.
  """

  alias Chronicle.EventSequences.TransactionalEventSequence

  @enforce_keys [:id]
  defstruct [:id, opts: []]

  @type t :: %__MODULE__{id: String.t(), opts: keyword()}

  @doc """
  Creates an event sequence wrapper for the given event sequence id.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id), do: %__MODULE__{id: id, opts: opts}

  @doc """
  Appends a single event to the event sequence.
  """
  @spec append(t(), String.t(), struct(), keyword()) :: :ok | {:error, term()}
  def append(%__MODULE__{} = event_sequence, event_source_id, event, opts \\ []) do
    Chronicle.EventSequences.EventLog.append(
      event_source_id,
      event,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Appends multiple events to the event sequence.
  """
  @spec append_many(t(), String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  def append_many(%__MODULE__{} = event_sequence, event_source_id, events, opts \\ []) do
    Chronicle.EventSequences.EventLog.append_many(
      event_source_id,
      events,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets events for the given event source from the event sequence.
  """
  @spec get_for_event_source(t(), String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_for_event_source(%__MODULE__{} = event_sequence, event_source_id, opts \\ []) do
    Chronicle.EventSequences.EventLog.get_for_event_source(
      event_source_id,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets the tail sequence number for the event sequence.
  """
  @spec get_tail_sequence_number(t(), String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_tail_sequence_number(%__MODULE__{} = event_sequence, event_source_id \\ nil, opts \\ []) do
    Chronicle.EventSequences.EventLog.get_tail_sequence_number(
      event_source_id,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets the sequence number that will be assigned to the next appended event.
  """
  @spec get_next_sequence_number(t(), String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_next_sequence_number(%__MODULE__{} = event_sequence, event_source_id \\ nil, opts \\ []) do
    Chronicle.EventSequences.EventLog.get_next_sequence_number(
      event_source_id,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets the tail sequence number scoped to only the event types the given
  reactor or reducer module subscribes to.
  """
  @spec get_tail_sequence_number_for_observer(t(), module(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_tail_sequence_number_for_observer(
        %__MODULE__{} = event_sequence,
        observer_module,
        opts \\ []
      ) do
    Chronicle.EventSequences.EventLog.get_tail_sequence_number_for_observer(
      observer_module,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets events from (and including) the given sequence number onward.
  """
  @spec get_from_sequence_number(t(), non_neg_integer(), keyword()) ::
          {:ok, list()} | {:error, term()}
  def get_from_sequence_number(%__MODULE__{} = event_sequence, sequence_number, opts \\ []) do
    Chronicle.EventSequences.EventLog.get_from_sequence_number(
      sequence_number,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Completes a named, non-default stream so that no further events can be
  appended to it.
  """
  @spec complete_stream(t(), String.t(), String.t(), keyword()) ::
          {:ok, non_neg_integer()}
          | {:error, :default_stream_cannot_be_completed | :already_completed | term()}
  def complete_stream(
        %__MODULE__{} = event_sequence,
        event_stream_type,
        event_stream_id,
        opts \\ []
      ) do
    Chronicle.EventSequences.EventLog.complete_stream(
      event_stream_type,
      event_stream_id,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Redacts a single event at a specific sequence number.
  """
  @spec redact(t(), non_neg_integer(), String.t(), keyword()) :: :ok | {:error, term()}
  def redact(%__MODULE__{} = event_sequence, sequence_number, reason, opts \\ []) do
    Chronicle.EventSequences.EventLog.redact(
      sequence_number,
      reason,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Redacts all events for a given event source, optionally filtered to
  specific event types.
  """
  @spec redact_for_event_source(t(), String.t(), String.t(), [module()], keyword()) ::
          :ok | {:error, term()}
  def redact_for_event_source(
        %__MODULE__{} = event_sequence,
        event_source_id,
        reason,
        event_types \\ [],
        opts \\ []
      ) do
    Chronicle.EventSequences.EventLog.redact_for_event_source(
      event_source_id,
      reason,
      event_types,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Checks whether the event sequence has events for the given event source id.
  """
  @spec has_events_for?(t(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def has_events_for?(%__MODULE__{} = event_sequence, event_source_id, opts \\ []) do
    Chronicle.EventSequences.EventLog.has_events_for?(
      event_source_id,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Appends a single event, then waits for every observer affected by the append
  to either reach the appended sequence number or fail.
  """
  @spec append_and_wait_for_completion(t(), String.t(), struct(), keyword()) ::
          {:ok, %{success: boolean(), failed_partitions: list()}} | {:error, term()}
  def append_and_wait_for_completion(
        %__MODULE__{} = event_sequence,
        event_source_id,
        event,
        opts \\ []
      ) do
    Chronicle.EventSequences.EventLog.append_and_wait_for_completion(
      event_source_id,
      event,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Appends a list of `Chronicle.EventSequences.EventForEventSourceId` entries as a
  single atomic append-many, each carrying its own target event source id.
  """
  @spec append_many_for_event_sources(
          t(),
          [Chronicle.EventSequences.EventForEventSourceId.t()],
          keyword()
        ) ::
          :ok | {:error, term()}
  def append_many_for_event_sources(%__MODULE__{} = event_sequence, events, opts \\ []) do
    Chronicle.EventSequences.EventLog.append_many_for_event_sources(
      events,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Gets a transactional view of the event sequence that buffers appends in the current unit of work.
  """
  @spec transactional(t()) :: TransactionalEventSequence.t()
  def transactional(%__MODULE__{} = event_sequence) do
    TransactionalEventSequence.new(event_sequence)
  end

  defp merge_opts(%__MODULE__{} = event_sequence, opts) do
    event_sequence.opts
    |> Keyword.put(:event_sequence_id, event_sequence.id)
    |> Keyword.merge(opts)
  end
end
