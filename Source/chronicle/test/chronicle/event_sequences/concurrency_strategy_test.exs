# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ConcurrencyStrategyTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.{ConcurrencyStrategy, EventForEventSourceId}

  @optimistic %{concurrency: [default: :optimistic]}

  defp event(event_source_id),
    do: %EventForEventSourceId{event_source_id: event_source_id, event: %{}}

  defp tail_fun(test) do
    fn event_source_id, _narrowing ->
      send(test, {:tail_read, event_source_id})
      {:ok, 7}
    end
  end

  test "the optimistic default scopes an event source with no other guard" do
    assert {:ok, [%{concurrency_scope: scope}]} =
             ConcurrencyStrategy.apply_default([event("a")], @optimistic, tail_fun(self()))

    assert scope != nil
    assert_received {:tail_read, "a"}
  end

  test "an event source with an enrolled decision read gets no default scope" do
    assert {:ok, [guarded, unguarded]} =
             ConcurrencyStrategy.apply_default(
               [event("guarded"), event("other")],
               @optimistic,
               tail_fun(self()),
               guarded_event_sources: ["guarded"]
             )

    assert guarded.concurrency_scope == nil
    assert unguarded.concurrency_scope != nil
    refute_received {:tail_read, "guarded"}
    assert_received {:tail_read, "other"}
  end
end
