# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.WireTest do
  use ExUnit.Case, async: true

  alias Chronicle.Auditing.CausationEntry
  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Imports.Wire
  alias Chronicle.ImportsFakeKernel.Event

  @correlation_id "8c3f6a1e-2b4d-4f6a-9c1b-2d3e4f5a6b7c"

  test "an imported event keeps everything its source says about it" do
    occurred = ~U[2019-05-04 03:02:01Z]

    entry = %EventForEventSourceId{
      event_source_id: "account-1",
      event: %Event{n: 7},
      event_source_type: "Account",
      event_stream_type: "Ledger",
      event_stream_id: "eu",
      tags: ["legacy"],
      named_tags: %{"region" => "eu"},
      subject: "person-1",
      occurred: occurred,
      correlation_id: @correlation_id,
      identity: Chronicle.Identity.new("user-1", "Ada", "ada"),
      causation: [
        %CausationEntry{
          occurred: occurred,
          type: Chronicle.Auditing.CausationType.new("Legacy"),
          properties: %{"batch" => "3"}
        }
      ],
      generation: 2,
      source_sequence_number: 41,
      idempotency_key: "legacy-41"
    }

    assert {:ok, event} = Wire.to_import_event(entry)

    assert event."EventSourceId" == "account-1"

    assert {event."EventSourceType", event."EventStreamType", event."EventStreamId"} ==
             {"Account", "Ledger", "eu"}

    assert event."EventType"."Id" == "imported-event"
    assert event."EventType"."Generation" == 2
    assert Jason.decode!(event."Content")["n"] == 7
    assert event."Tags" == ["legacy"]
    assert [%{Name: "region", Value: "eu"}] = event."NamedTags"
    assert event."Occurred"."Value" == DateTime.to_iso8601(occurred)
    assert event."Subject" == "person-1"
    assert Wire.guid_to_string(event."CorrelationId") == @correlation_id
    assert %{Subject: "user-1", Name: "Ada", UserName: "ada"} = event."CausedBy"
    assert [%{Type: "Legacy", Properties: %{"batch" => "3"}}] = event."Causation"
    assert event."SourceSequenceNumber" == 41
    assert event."IdempotencyKey" == "legacy-41"
  end

  test "an event without import metadata leaves it to the kernel" do
    assert {:ok, event} =
             Wire.to_import_event(%EventForEventSourceId{event_source_id: "a", event: %Event{}})

    assert event."EventType"."Generation" == 1
    assert event."CorrelationId" == nil
    assert event."CausedBy" == nil
    assert event."Occurred" == nil
    assert event."SourceSequenceNumber" == 0
  end

  test "a GUID survives the round trip through the wire form" do
    assert @correlation_id |> Wire.guid() |> Wire.guid_to_string() == @correlation_id
  end

  test "maps every import state" do
    assert Enum.map(0..6, &Wire.state/1) ==
             [:open, :staging, :validating, :committing, :completed, :failed, :abandoned]

    assert Wire.state(:Committing) == :committing
  end
end
