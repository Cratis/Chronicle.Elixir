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
