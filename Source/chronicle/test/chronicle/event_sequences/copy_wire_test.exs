# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.CopyWireTest do
  use Chronicle.AppendWireCase

  alias Bcl.Guid, as: BclGuid
  alias Chronicle.EventSequences.EventSequence

  @job_id "00112233-4455-6677-8899-aabbccddeeff"

  defmodule Other do
    use Chronicle.Events.EventType, id: "copy-wire-other"
    defstruct [:value]
  end

  # protobuf-net Guid carries Guid.ToByteArray() in two little-endian words.
  defp guid(uuid) do
    <<first::32, second::16, third::16, remaining::binary-size(8)>> =
      uuid |> String.replace("-", "") |> Base.decode16!(case: :mixed)

    <<lo::little-64, hi::little-64>> =
      <<first::little-32, second::little-16, third::little-16, remaining::binary>>

    struct(BclGuid, lo: lo, hi: hi)
  end

  setup do
    put_response(:copy_job_id, guid(@job_id))
    :ok
  end

  test "sends source, target and no event types, and returns the job id", %{opts: opts} do
    assert {:ok, @job_id} = EventLog.copy("source", "target", [], opts)

    assert %Wire.CopyEventsForEventSourceRequest{
             EventStore: "store",
             Namespace: "namespace",
             EventSequenceId: "event-log",
             SourceId: "source",
             TargetId: "target",
             EventTypes: []
           } = take_request()
  end

  test "resolves event type ids from the event type modules", %{opts: opts} do
    assert {:ok, @job_id} = EventLog.copy("source", "target", [Event, Other], opts)
    assert %Wire.CopyEventsForEventSourceRequest{EventTypes: types} = take_request()
    assert types == ["append-wire-event", "copy-wire-other"]
  end

  test "honors namespace and event sequence id options", %{opts: opts} do
    opts = Keyword.merge(opts, namespace: "other-ns", event_sequence_id: "outbox")
    assert {:ok, _} = EventLog.copy("source", "target", [], opts)

    assert %Wire.CopyEventsForEventSourceRequest{Namespace: "other-ns", EventSequenceId: "outbox"} =
             take_request()
  end

  test "is available on an event sequence handle", %{opts: opts} do
    sequence = EventSequence.new("inbox", opts)
    assert {:ok, @job_id} = EventSequence.copy(sequence, "source", "target", [Event])
    assert %Wire.CopyEventsForEventSourceRequest{EventSequenceId: "inbox"} = take_request()
  end

  test "surfaces an unauthorized result as an error", %{opts: opts} do
    put_response(:envelope, IsAuthorized: false, AuthorizationFailureReason: "nope")
    assert {:error, {:unauthorized, "nope"}} = EventLog.copy("source", "target", [], opts)
  end

  test "surfaces kernel exceptions as an error", %{opts: opts} do
    put_response(:envelope, ExceptionMessages: ["boom"])
    assert {:error, {:exception, ["boom"]}} = EventLog.copy("source", "target", [], opts)
  end
end
