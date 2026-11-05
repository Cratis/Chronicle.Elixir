# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.EventBatchTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.EventContext

  alias Chronicle.Observers.{
    DeferralNotSupportedByKernel,
    EventBatch,
    PartitionNotInBatch
  }

  defmodule Registered do
    defstruct [:name]
  end

  defp context(event_source_id, sequence_number),
    do: %EventContext{event_source_id: event_source_id, sequence_number: sequence_number}

  defp batch(can_defer? \\ true) do
    EventBatch.new(
      [
        {"a", %Registered{name: "first"}, context("a", 1)},
        {"b", %Registered{name: "second"}, context("b", 2)},
        {"a", %Registered{name: "third"}, context("a", 3)}
      ],
      can_defer?
    )
  end

  test "enumerates its events and contexts in sequence order" do
    assert Enum.map(batch(), fn {%Registered{name: name}, context} ->
             {name, context.sequence_number}
           end) == [{"first", 1}, {"second", 2}, {"third", 3}]
  end

  test "knows its partitions and size" do
    assert EventBatch.partitions(batch()) == ["a", "b"]
    assert EventBatch.count(batch()) == 3
    assert Enum.count(batch()) == 3
  end

  test "fails a partition from its first event in the batch" do
    assert [%{partition: "a", at: 1, kind: :failed, reason: :unavailable}] =
             batch() |> EventBatch.fail("a", :unavailable) |> EventBatch.outcomes()
  end

  test "fails a partition from the event a context points at" do
    assert [%{partition: "a", at: 3, kind: :failed}] =
             batch() |> EventBatch.fail(context("a", 3), :bad) |> EventBatch.outcomes()
  end

  test "defers a partition with a delay" do
    assert [%{partition: "b", at: 2, kind: :deferred, retry_after: 500}] =
             batch() |> EventBatch.defer("b", 500) |> EventBatch.outcomes()
  end

  test "fails a deferral when the kernel did not deliver a page" do
    assert [%{kind: :failed, reason: %DeferralNotSupportedByKernel{partition: "b"}}] =
             batch(false) |> EventBatch.defer("b", 500) |> EventBatch.outcomes()
  end

  test "refuses a partition it does not hold" do
    assert_raise PartitionNotInBatch, fn -> EventBatch.fail(batch(), "z", :bad) end
    assert_raise PartitionNotInBatch, fn -> EventBatch.defer(batch(), context("a", 9), 10) end
  end
end
