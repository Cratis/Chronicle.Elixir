# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionSchedulerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.PartitionScheduler

  defp schedule(scheduler, entries) do
    entries
    |> Enum.reduce(scheduler, &PartitionScheduler.enqueue(&2, &1))
    |> PartitionScheduler.schedule()
  end

  test "starts batches for different partitions together" do
    {actions, _} = schedule(PartitionScheduler.new(4), [{:batch, "a", 1}, {:batch, "b", 2}])
    assert actions == [{:start, "a", 1}, {:start, "b", 2}]
  end

  test "runs one batch per partition at a time, in order" do
    {actions, scheduler} =
      schedule(PartitionScheduler.new(4), [{:batch, "a", 1}, {:batch, "a", 2}, {:batch, "b", 3}])

    assert actions == [{:start, "a", 1}, {:start, "b", 3}]

    {actions, _} = scheduler |> PartitionScheduler.complete("a") |> PartitionScheduler.schedule()
    assert actions == [{:start, "a", 2}]
  end

  test "never has more batches in flight than allowed" do
    {actions, scheduler} =
      schedule(PartitionScheduler.new(2), [{:batch, "a", 1}, {:batch, "b", 2}, {:batch, "c", 3}])

    assert actions == [{:start, "a", 1}, {:start, "b", 2}]
    assert PartitionScheduler.in_flight(scheduler) == 2
    assert PartitionScheduler.queue_depth(scheduler) == 1

    {actions, _} = scheduler |> PartitionScheduler.complete("b") |> PartitionScheduler.schedule()
    assert actions == [{:start, "c", 3}]
  end

  test "keeps a partition's later batch behind one that waits for capacity" do
    {_, scheduler} = schedule(PartitionScheduler.new(1), [{:batch, "a", 1}, {:batch, "b", 2}])
    {actions, _} = schedule(scheduler, [{:batch, "b", 3}])
    assert actions == []

    {actions, scheduler} =
      scheduler
      |> PartitionScheduler.enqueue({:batch, "b", 3})
      |> PartitionScheduler.complete("a")
      |> PartitionScheduler.schedule()

    assert actions == [{:start, "b", 2}]

    {actions, _} = scheduler |> PartitionScheduler.complete("b") |> PartitionScheduler.schedule()
    assert actions == [{:start, "b", 3}]
  end

  test "runs a partition's inline item after its earlier batches" do
    {actions, scheduler} =
      schedule(PartitionScheduler.new(4), [
        {:batch, "a", 1},
        {:inline, "a", :end},
        {:batch, "b", 2}
      ])

    assert actions == [{:start, "a", 1}, {:start, "b", 2}]

    {actions, _} = scheduler |> PartitionScheduler.complete("a") |> PartitionScheduler.schedule()
    assert actions == [{:run, :end}]
  end

  test "runs a barrier only when everything before it has finished, and holds what follows" do
    {actions, scheduler} =
      schedule(PartitionScheduler.new(4), [{:batch, "a", 1}, {:barrier, :end}, {:batch, "b", 2}])

    assert actions == [{:start, "a", 1}]

    {actions, _} = scheduler |> PartitionScheduler.complete("a") |> PartitionScheduler.schedule()
    assert actions == [{:run, :end}, {:start, "b", 2}]
  end

  test "forgets everything on reset" do
    {_, scheduler} = schedule(PartitionScheduler.new(1), [{:batch, "a", 1}, {:batch, "b", 2}])
    scheduler = PartitionScheduler.reset(scheduler)

    assert PartitionScheduler.in_flight(scheduler) == 0
    assert PartitionScheduler.queue_depth(scheduler) == 0
  end
end
