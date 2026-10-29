# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionScheduler do
  @moduledoc false

  # Decides what an observer handler runs next, so batches for different
  # partitions run concurrently while each partition's batches run in order.
  #
  # Work arrives as an ordered list of entries:
  #
  #   * `{:batch, partition, item}` runs as a task. At most one batch per
  #     partition is in flight, and at most `max_in_flight` overall.
  #   * `{:inline, partition, item}` runs in the handler process once every
  #     earlier entry for its partition has finished (partition replay
  #     notifications).
  #   * `{:barrier, item}` runs in the handler process once everything before it
  #     has finished, and nothing after it starts until it has run (replay
  #     begin/end notifications).
  #
  # The scheduler is pure: `schedule/1` returns the actions to take, in order,
  # and the handler performs them.

  defstruct pending: [], in_flight: MapSet.new(), max_in_flight: 1

  @type partition :: term()
  @type entry ::
          {:batch, partition(), term()} | {:inline, partition(), term()} | {:barrier, term()}
  @type action :: {:start, partition(), term()} | {:run, term()}
  @type t :: %__MODULE__{
          pending: [entry()],
          in_flight: MapSet.t(partition()),
          max_in_flight: pos_integer()
        }

  @doc "Creates a scheduler that runs at most `max_in_flight` batches at a time."
  @spec new(pos_integer()) :: t()
  def new(max_in_flight) when is_integer(max_in_flight) and max_in_flight > 0,
    do: %__MODULE__{max_in_flight: max_in_flight}

  @doc "Adds an entry behind everything already pending."
  @spec enqueue(t(), entry()) :: t()
  def enqueue(%__MODULE__{} = scheduler, entry),
    do: %{scheduler | pending: scheduler.pending ++ [entry]}

  @doc "Marks the batch in flight for `partition` as finished."
  @spec complete(t(), partition()) :: t()
  def complete(%__MODULE__{} = scheduler, partition),
    do: %{scheduler | in_flight: MapSet.delete(scheduler.in_flight, partition)}

  @doc "Drops everything pending and forgets what is in flight."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = scheduler), do: %{scheduler | pending: [], in_flight: MapSet.new()}

  @doc "How many entries wait to run."
  @spec queue_depth(t()) :: non_neg_integer()
  def queue_depth(%__MODULE__{pending: pending}), do: length(pending)

  @doc "How many batches are in flight."
  @spec in_flight(t()) :: non_neg_integer()
  def in_flight(%__MODULE__{in_flight: in_flight}), do: MapSet.size(in_flight)

  @doc """
  Returns the actions that can be taken now, in order, and the scheduler with
  started batches marked in flight and run entries removed.
  """
  @spec schedule(t()) :: {[action()], t()}
  def schedule(%__MODULE__{} = scheduler) do
    {actions, kept, in_flight} =
      scan(scheduler.pending, [], [], scheduler.in_flight, MapSet.new(), scheduler.max_in_flight)

    {actions, %{scheduler | pending: kept, in_flight: in_flight}}
  end

  # `held` holds partitions that already have an earlier entry still waiting,
  # so later entries for them must wait too.
  defp scan([], actions, kept, in_flight, _held, _max),
    do: {Enum.reverse(actions), Enum.reverse(kept), in_flight}

  defp scan([{:barrier, item} = entry | rest], actions, kept, in_flight, held, max) do
    if kept == [] and MapSet.size(in_flight) == 0 do
      scan(rest, [{:run, item} | actions], kept, in_flight, held, max)
    else
      # Nothing behind a barrier may start before it has run.
      {Enum.reverse(actions), Enum.reverse(kept) ++ [entry | rest], in_flight}
    end
  end

  defp scan([{:inline, partition, item} = entry | rest], actions, kept, in_flight, held, max) do
    if waiting?(partition, in_flight, held) do
      scan(rest, actions, [entry | kept], in_flight, MapSet.put(held, partition), max)
    else
      scan(rest, [{:run, item} | actions], kept, in_flight, held, max)
    end
  end

  defp scan([{:batch, partition, item} = entry | rest], actions, kept, in_flight, held, max) do
    if waiting?(partition, in_flight, held) or MapSet.size(in_flight) >= max do
      scan(rest, actions, [entry | kept], in_flight, MapSet.put(held, partition), max)
    else
      scan(
        rest,
        [{:start, partition, item} | actions],
        kept,
        MapSet.put(in_flight, partition),
        held,
        max
      )
    end
  end

  defp waiting?(partition, in_flight, held),
    do: MapSet.member?(in_flight, partition) or MapSet.member?(held, partition)
end
