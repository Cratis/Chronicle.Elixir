# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.StreamsTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.{EventLog, Streams}

  test "closed streams decode their scope, origin and closure" do
    closed =
      Streams.decode_closed_stream(%{
        EventSourceId: "e1",
        EventStreamType: "Period",
        EventStreamId: "2024",
        Origin: :ClosingEvent,
        ClosedBy: "books-closed",
        SequenceNumber: 9,
        ClosedAt: %{Value: "2024-12-31T00:00:00Z"}
      })

    assert closed.origin == :closing_event
    assert closed.event_stream_id == "2024"
    assert closed.sequence_number == 9
    assert closed.closed_at == "2024-12-31T00:00:00Z"
    assert Streams.decode_closed_stream(%{Origin: :CompleteStream}).origin == :complete_stream
  end

  test "complete stream responses decode into a sequence number or a named error" do
    assert EventLog.decode_complete_stream_response(%{IsSuccess: true, SequenceNumber: 4}) ==
             {:ok, 4}

    assert EventLog.decode_complete_stream_response(%{IsSuccess: false, Error: :EmptyScope}) ==
             {:error, :empty_scope}

    assert EventLog.decode_complete_stream_response(%{
             IsSuccess: false,
             Error: :ExpectedTailMismatch
           }) ==
             {:error, :expected_tail_mismatch}

    assert EventLog.decode_complete_stream_response(%{IsSuccess: false, Error: :AlreadyCompleted}) ==
             {:error, :already_completed}

    assert EventLog.decode_complete_stream_response(%{
             IsSuccess: false,
             Error: :DefaultStreamCannotBeCompleted
           }) == {:error, :default_stream_cannot_be_completed}
  end

  test "reopen outcomes" do
    assert Streams.decode_reopen(%{IsSuccess: true}) == :ok

    assert Streams.decode_reopen(%{IsSuccess: false, Error: :NotCompleted}) ==
             {:error, :not_completed}

    assert Streams.decode_reopen(%{IsSuccess: false, Error: :ClosedByEvent}) ==
             {:error, :closed_by_event}
  end

  test "content verification outcomes" do
    assert Streams.decode_verification(:Equal) == :equal
    assert Streams.decode_verification(:Different) == :different
    assert Streams.decode_verification(:Unavailable) == :unavailable
  end

  test "metadata decodes who, when and why" do
    metadata =
      Streams.decode_metadata(%{
        SequenceNumber: 5,
        EventTypeId: "opened",
        EventSourceId: "a1",
        Occurred: %{Value: "2024-01-01T00:00:00Z"},
        CausedBy: %{Subject: "u1", Name: "Ada", UserName: "ada"},
        Tags: ["t"],
        Subject: "u1",
        EventSourceName: ""
      })

    assert metadata.sequence_number == 5
    assert metadata.caused_by.name == "Ada"
    assert metadata.tags == ["t"]
    assert metadata.occurred == "2024-01-01T00:00:00Z"
  end

  test "metadata decodes initiator type" do
    assert Streams.decode_metadata(%{InitiatorType: :User}).initiator_type == :user
    assert Streams.decode_metadata(%{InitiatorType: :Agent}).initiator_type == :agent

    assert Streams.decode_metadata(%{InitiatorType: :INITIATOR_TYPE_System}).initiator_type ==
             :system

    assert Streams.decode_metadata(%{}).initiator_type == :unknown
  end

  test "metadata decodes the resolved identity, including resolution and on-behalf-of" do
    metadata =
      Streams.decode_metadata(%{
        CausedBy: %{
          Subject: "agent-1",
          Name: "Agent",
          UserName: "agent",
          Resolution: :Resolved,
          OnBehalfOf: %{
            Subject: "u1",
            Name: "Ada",
            UserName: "ada",
            Resolution: :Missing
          }
        }
      })

    assert metadata.caused_by.name == "Agent"
    assert metadata.caused_by.on_behalf_of.name == "Ada"

    assert metadata.resolved_caused_by == %Chronicle.EventSequences.ResolvedIdentity{
             subject: "agent-1",
             name: "Agent",
             user_name: "agent",
             resolution: :resolved,
             on_behalf_of: %Chronicle.EventSequences.ResolvedIdentity{
               subject: "u1",
               name: "Ada",
               user_name: "ada",
               resolution: :missing,
               on_behalf_of: nil
             }
           }
  end

  test "metadata resolution falls back to :not_set for an unrecognized value" do
    metadata = Streams.decode_metadata(%{CausedBy: %{Subject: "s", Name: "n"}})
    assert metadata.resolved_caused_by.resolution == :not_set
    assert metadata.caused_by.subject == "s"
  end
end
