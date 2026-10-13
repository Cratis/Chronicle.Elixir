# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventContextTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.EventContext

  defp wire do
    %{
      EventType: %{Id: "funds-deposited", Generation: 2},
      EventSourceType: "Account",
      EventSourceId: "acc-1",
      EventStreamType: "All",
      EventStreamId: "Default",
      SequenceNumber: 42,
      Occurred: %{Value: "2024-01-01T00:00:00Z"},
      EventStore: "store",
      Namespace: "ns",
      CorrelationId: %{lo: 0x0807060504030201, hi: 0x100F0E0D0C0B0A09},
      CausedBy: %{
        Subject: "u1",
        Name: "Ada",
        UserName: "ada",
        OnBehalfOf: %{Subject: "u2", Name: "Bob"}
      },
      Causation: [
        %{
          Occurred: %{Value: ~U[2024-01-01 00:00:00Z]},
          Type: "http",
          Properties: %{"path" => "/x"}
        }
      ],
      Tags: ["a"],
      NamedTags: [%{Name: "k", Value: "v"}],
      Hash: "h",
      Subject: "u1",
      EventSource: "",
      AppendedGeneration: 2
    }
  end

  test "builds a complete context from the wire representation" do
    ctx = EventContext.from_wire(wire(), event_sequence_id: "event-log", reactor_id: "my-reactor")

    assert ctx.event_source_id == "acc-1"
    assert ctx.event_type == %{id: "funds-deposited", generation: 2}
    assert ctx.caused_by.subject == "u1"
    assert ctx.caused_by.on_behalf_of.name == "Bob"
    assert [%{type: %{value: "http"}, properties: %{"path" => "/x"}}] = ctx.causation
    assert ctx.correlation_id == "04030201-0605-0807-090a-0b0c0d0e0f10"
    assert ctx.tags == ["a"]
    assert ctx.named_tags == %{"k" => "v"}
    assert ctx.event_source == nil
    assert ctx.appended_generation == 2
    assert ctx.event_store == "store"
    assert ctx.namespace == "ns"
  end

  test "delivery id is stable and matches the .NET derivation" do
    ctx = EventContext.from_wire(wire(), event_sequence_id: "event-log", reactor_id: "my-reactor")

    again =
      EventContext.from_wire(wire(), event_sequence_id: "event-log", reactor_id: "my-reactor")

    assert ctx.delivery_id == "my-reactor#store#ns#event-log#acc-1#42"
    assert ctx.delivery_id == again.delivery_id

    other = EventContext.from_wire(wire(), event_sequence_id: "other", reactor_id: "my-reactor")
    refute other.delivery_id == ctx.delivery_id
  end

  test "without a reactor there is no delivery id and a bare context still works" do
    ctx = EventContext.from_wire(%{EventSourceId: "a"})
    assert ctx.delivery_id == nil
    assert ctx.event_source_id == "a"
    assert ctx.caused_by == nil
    assert ctx.causation == []
  end
end
