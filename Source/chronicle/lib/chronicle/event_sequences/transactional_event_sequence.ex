# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.TransactionalEventSequence do
  @moduledoc """
  Transactional view of an event sequence.

  Appends are buffered in the current unit of work and are only sent to Chronicle
  when the unit of work is committed.
  """

  alias Chronicle.EventSequences.EventSequence

  @enforce_keys [:event_sequence]
  defstruct [:event_sequence]

  @type t :: %__MODULE__{event_sequence: EventSequence.t()}

  @doc """
  Creates a transactional event sequence wrapper.
  """
  @spec new(EventSequence.t()) :: t()
  def new(%EventSequence{} = event_sequence), do: %__MODULE__{event_sequence: event_sequence}

  @doc """
  Buffers a single event append in the current unit of work.
  """
  @spec append(t(), String.t(), struct(), keyword()) :: :ok
  def append(%__MODULE__{event_sequence: event_sequence}, event_source_id, event, opts \\ []) do
    Chronicle.EventLog.buffer_append(
      event_sequence.id,
      event_source_id,
      event,
      merge_opts(event_sequence, opts)
    )
  end

  @doc """
  Buffers multiple event appends in the current unit of work.
  """
  @spec append_many(t(), String.t(), [struct()], keyword()) :: :ok
  def append_many(
        %__MODULE__{} = transactional_event_sequence,
        event_source_id,
        events,
        opts \\ []
      ) do
    Enum.each(events, fn event ->
      append(transactional_event_sequence, event_source_id, event, opts)
    end)

    :ok
  end

  defp merge_opts(%EventSequence{} = event_sequence, opts) do
    event_sequence.opts
    |> Keyword.put(:event_sequence_id, event_sequence.id)
    |> Keyword.merge(opts)
  end
end
