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
end
