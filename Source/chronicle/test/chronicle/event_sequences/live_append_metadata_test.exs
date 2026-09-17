# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.LiveAppendMetadataTest do
  use ExUnit.Case, async: false

  alias Chronicle.Auditing.{CausationEntry, CausationType}
  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Identity

  # Opt in against an isolated kernel with a complete, authenticated connection
  # string. No credential fallback: an anonymous URI must not silently impersonate
  # the development client. Each run owns a fresh namespace and leaves it intact.
  @connection System.get_env("CHRONICLE_INTEROP_CONNECTION")
  @moduletag skip: is_nil(@connection)
  @moduletag timeout: 60_000
  @client :live_append_metadata
  @occurred ~U[2020-01-01 00:00:00.123456Z]
  @correlation "00112233-4455-6677-8899-aabbccddeeff"

  defmodule Event do
    use Chronicle.Events.EventType, id: "ElixirLiveMetadataRecorded"
    defstruct value: ""
  end

  setup_all do
    namespace = "metadata-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"

    start_supervised!(
      {Chronicle.Client,
       name: @client,
       connection_string: @connection,
       event_store: "elixir-interop",
       namespace: namespace,
       discover: false,
       event_types: [Event]}
    )

    assert :ok = Lifecycle.wait_until(Lifecycle.name_for(@client), :registered, 30_000)
    :ok
  end

  for path <- [:single, :batch], metadata <- [:default, :explicit] do
    test "#{path} persists #{metadata} metadata and payloads in append order" do
      source = "#{unquote(path)}-#{unquote(metadata)}"
      values = if unquote(path) == :single, do: ["first"], else: ["first", "second"]
      events = Enum.map(values, &%Event{value: &1})
      options = [client: @client] ++ metadata_options(unquote(metadata))

      assert :ok = append(unquote(path), source, events, options)
      stored = read(source)
      assert length(stored) == length(events)
      assert Enum.map(stored, &Jason.decode!(&1."Content")["value"]) == values

      contexts = Enum.map(stored, & &1."Context")
      positions = Enum.map(contexts, & &1."SequenceNumber")
      assert positions == Enum.sort(Enum.uniq(positions))

      for context <- contexts do
        assert context."EventSourceId" == source
        assert context."EventType"."Id" == "ElixirLiveMetadataRecorded"
        assert context."EventType"."Generation" == 1
        assert {:ok, _, 0} = DateTime.from_iso8601(context."Occurred"."Value")
        assert_metadata(context, unquote(metadata))
      end
    end
  end

  for path <- [:single, :batch] do
    test "#{path} rejects a stale source scope without persisting any attempted event" do
      source = "stale-#{unquote(path)}"
      assert :ok = EventLog.append(source, %Event{value: "first"}, client: @client)
      [first] = read(source)
      assert :ok = EventLog.append(source, %Event{value: "second"}, client: @client)
      before_rejection = read(source)
      assert length(before_rejection) == 2

      options = [
        client: @client,
        concurrency_scope: ConcurrencyScope.for_event_source(first."Context"."SequenceNumber")
      ]

      attempts =
        if unquote(path) == :single,
          do: [%Event{value: "rejected"}],
          else: [%Event{value: "rejected-one"}, %Event{value: "rejected-two"}]

      assert {:error, {:concurrency_violations, [_ | _]}} =
               append(unquote(path), source, attempts, options)

      assert read(source) == before_rejection
    end
  end

  defp metadata_options(:default), do: []

  defp metadata_options(:explicit) do
    cause = CausationEntry.new(CausationType.append_event(), %{reason: "interop"})

    [
      event_source_type: "Account",
      event_stream_type: "Payments",
      event_stream_id: "explicit",
      subject: "person",
      tags: ["interop", "metadata"],
      occurred: @occurred,
      correlation_id: @correlation,
      identity: Identity.new("actor", "Actor", "actor-name"),
      causation: [cause]
    ]
  end

  defp assert_metadata(context, :default) do
    assert context."EventSourceType" == "Default"
    assert context."EventStreamType" == "All"
    assert context."EventStreamId" == "Default"
    assert context."Tags" == []
  end

  defp assert_metadata(context, :explicit) do
    assert context."EventSourceType" == "Account"
    assert context."EventStreamType" == "Payments"
    assert context."EventStreamId" == "explicit"
    assert context."Subject" == "person"
    assert context."Tags" == ["interop", "metadata"]
    assert {:ok, @occurred, 0} == DateTime.from_iso8601(context."Occurred"."Value")
    assert context."CorrelationId".lo == 0x6677445500112233
    assert context."CorrelationId".hi == 0xFFEEDDCCBBAA9988
    assert context."CausedBy"."Subject" == "actor"
    assert context."CausedBy"."Name" == "Actor"
    assert context."CausedBy"."UserName" == "actor-name"
    assert Enum.any?(context."Causation", &(&1."Properties" == %{"reason" => "interop"}))
  end

  defp append(:single, source, [event], options), do: EventLog.append(source, event, options)
  defp append(:batch, source, events, options), do: EventLog.append_many(source, events, options)

  defp read(source) do
    assert {:ok, events} =
             EventLog.get_from_sequence_number(0, client: @client, event_source_id: source)

    events
  end
end
