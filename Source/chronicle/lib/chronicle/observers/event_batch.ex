# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.EventBatch do
  @moduledoc """
  The events a batch function receives, in sequence order, together with what the function
  reports about them.

  A batch function of a reactor or reducer (see `Chronicle.Reactors.Reactor` and
  `Chronicle.Reducers.Reducer`) receives an `EventBatch` holding the events of the types it
  declares with `@observes`. It is enumerable: each element is an `{event, context}` tuple, where
  `context` is the event's `Chronicle.Events.EventContext`, so a batch function pattern-matches
  on the events it receives:

      Enum.map(batch, fn
        {%UserRegistered{name: name}, context} -> {:upsert, context.event_source_id, name}
        {%UserRemoved{}, context} -> {:delete, context.event_source_id}
      end)

  ## Reporting outcomes

  An `EventBatch` is immutable. `fail/3` and `defer/3` return a new batch that records the
  outcome, and the batch function returns that batch so Chronicle can settle each partition:

    * `fail(batch, partition, reason)` fails a partition from its first event in the batch;
      `fail(batch, context, reason)` fails it from that event. For reactors, the partition's
      earlier events count as handled.
    * `defer(batch, partition, retry_after_ms)` and `defer(batch, context, retry_after_ms)` ask
      Chronicle to deliver the partition again, from that point, after the delay. A deferral is
      not a failure and does not count towards quarantine. A kernel that does not deliver pages
      cannot defer; the partition is then failed with
      `Chronicle.Observers.DeferralNotSupportedByKernel` as the reason.

  When a partition is reported more than once, it settles at the earliest event reported.
  """

  alias Chronicle.Observers.{DeferralNotSupportedByKernel, PartitionNotInBatch}

  @typedoc "An event of the batch together with its context."
  @type element :: {struct(), Chronicle.Events.EventContext.t()}

  @typedoc "What a batch function reported for a partition."
  @type outcome :: %{
          partition: String.t(),
          at: non_neg_integer(),
          kind: :failed | :deferred,
          reason: term(),
          retry_after: non_neg_integer()
        }

  @typedoc """
  A partition (its event source id) or the context of one event in the batch.
  """
  @type target :: String.t() | Chronicle.Events.EventContext.t()

  @type t :: %__MODULE__{
          entries: [{String.t(), struct(), Chronicle.Events.EventContext.t()}],
          can_defer?: boolean(),
          outcomes: [outcome()]
        }

  defstruct entries: [], can_defer?: true, outcomes: []

  @doc false
  @spec new([{String.t(), struct(), Chronicle.Events.EventContext.t()}], boolean()) :: t()
  def new(entries, can_defer?), do: %__MODULE__{entries: entries, can_defer?: can_defer?}

  @doc "The events of the batch, as `{event, context}` tuples in sequence order."
  @spec events(t()) :: [element()]
  def events(%__MODULE__{entries: entries}),
    do: Enum.map(entries, fn {_partition, event, context} -> {event, context} end)

  @doc "The distinct partitions (event source ids) in the batch, in order of first appearance."
  @spec partitions(t()) :: [String.t()]
  def partitions(%__MODULE__{entries: entries}),
    do: entries |> Enum.map(fn {partition, _event, _context} -> partition end) |> Enum.uniq()

  @doc "How many events the batch holds."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: length(entries)

  @doc """
  Fails a partition from its first event in the batch, or, given an event's context, from that
  event. Raises `Chronicle.Observers.PartitionNotInBatch` for a partition the batch does not hold.
  """
  @spec fail(t(), target(), term()) :: t()
  def fail(%__MODULE__{} = batch, target, reason) do
    {partition, at} = locate!(batch, target)
    record(batch, %{partition: partition, at: at, kind: :failed, reason: reason, retry_after: 0})
  end

  @doc """
  Defers a partition from its first event in the batch, or, given an event's context, from that
  event, to be delivered again after `retry_after_ms` milliseconds. Raises
  `Chronicle.Observers.PartitionNotInBatch` for a partition the batch does not hold.
  """
  @spec defer(t(), target(), non_neg_integer()) :: t()
  def defer(%__MODULE__{} = batch, target, retry_after_ms)
      when is_integer(retry_after_ms) and retry_after_ms >= 0 do
    {partition, at} = locate!(batch, target)

    outcome =
      if batch.can_defer? do
        %{partition: partition, at: at, kind: :deferred, reason: nil, retry_after: retry_after_ms}
      else
        %{
          partition: partition,
          at: at,
          kind: :failed,
          reason: DeferralNotSupportedByKernel.exception(partition: partition),
          retry_after: 0
        }
      end

    record(batch, outcome)
  end

  @doc "The outcomes reported so far, in the order they were reported."
  @spec outcomes(t()) :: [outcome()]
  def outcomes(%__MODULE__{outcomes: outcomes}), do: Enum.reverse(outcomes)

  defp record(batch, outcome), do: %{batch | outcomes: [outcome | batch.outcomes]}

  defp locate!(batch, partition) when is_binary(partition) do
    case Enum.find(batch.entries, fn {p, _event, context} ->
           p == partition or context.event_source_id == partition
         end) do
      {p, _event, context} -> {p, context.sequence_number}
      nil -> raise PartitionNotInBatch, partition: partition
    end
  end

  defp locate!(batch, %{event_source_id: event_source_id, sequence_number: sequence_number}) do
    case Enum.find(batch.entries, fn {_p, _event, context} ->
           context.event_source_id == event_source_id and
             context.sequence_number == sequence_number
         end) do
      {p, _event, _context} -> {p, sequence_number}
      nil -> raise PartitionNotInBatch, partition: event_source_id
    end
  end

  defimpl Enumerable do
    def count(batch), do: {:ok, length(batch.entries)}
    def member?(_batch, _element), do: {:error, __MODULE__}
    def slice(_batch), do: {:error, __MODULE__}

    def reduce(batch, acc, fun),
      do: Enumerable.List.reduce(Chronicle.Observers.EventBatch.events(batch), acc, fun)
  end
end
