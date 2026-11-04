# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.CompensateWireTest do
  use Chronicle.AppendWireCase

  alias Chronicle.EventSequences.{AppendResult, EventSequence}

  defmodule Compensation do
    use Chronicle.Events.EventType,
      id: "compensate-wire-compensation",
      compensation_for: Chronicle.AppendWireCase.Event

    defstruct [:reason]
  end

  defmodule NotAnEvent do
    defstruct [:reason]
  end

  test "sends the compensated sequence number, event type and content", %{opts: opts} do
    put_response(:append_payload, IsSuccess: true, SequenceNumbers: [7])

    assert {:ok, %AppendResult{success?: true}} =
             EventLog.compensate(3, %Compensation{reason: "typo"}, opts)

    assert %Wire.CompensateRequest{
             EventStore: "store",
             Namespace: "namespace",
             EventSequenceId: "event-log",
             CompensationFor: 3,
             EventType: %Wire.EventType{Id: "compensate-wire-compensation"},
             Content: content
           } = take_request()

    assert content =~ "typo"
  end

  test "carries tags and honors namespace and event sequence id", %{opts: opts} do
    opts = Keyword.merge(opts, tags: ["a"], namespace: "other-ns", event_sequence_id: "outbox")
    assert {:ok, _} = EventLog.compensate(0, %Compensation{reason: "x"}, opts)

    assert %Wire.CompensateRequest{
             Namespace: "other-ns",
             EventSequenceId: "outbox",
             CompensationFor: 0,
             Tags: ["a"]
           } = take_request()
  end

  test "is available on an event sequence handle", %{opts: opts} do
    sequence = EventSequence.new("inbox", opts)
    assert {:ok, _} = EventSequence.compensate(sequence, 5, %Compensation{reason: "x"})
    assert %Wire.CompensateRequest{EventSequenceId: "inbox", CompensationFor: 5} = take_request()
  end

  test "refuses a struct that is not an event type", %{opts: opts} do
    assert {:error, {:unknown_event_type, NotAnEvent}} =
             EventLog.compensate(1, %NotAnEvent{reason: "x"}, opts)
  end

  test "surfaces a kernel rejection as an error result", %{opts: opts} do
    put_response(:append_payload, IsSuccess: false, Errors: ["nope"])

    assert {:error, %AppendResult{success?: false}} =
             EventLog.compensate(1, %Compensation{}, opts)
  end

  test "surfaces an unauthorized result as an error", %{opts: opts} do
    put_response(:envelope, IsAuthorized: false, AuthorizationFailureReason: "nope")
    assert {:error, {:unauthorized, "nope"}} = EventLog.compensate(1, %Compensation{}, opts)
  end
end
