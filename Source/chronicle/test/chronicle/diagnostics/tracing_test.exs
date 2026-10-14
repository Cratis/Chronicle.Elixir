# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Diagnostics.TracingTest do
  use ExUnit.Case, async: false

  alias Chronicle.Diagnostics.Tracing

  describe "with_span/3" do
    test "returns the wrapped function's result" do
      assert Tracing.with_span("cratis.chronicle.client.event_sequence.append", %{}, fn -> :ok end) ==
               :ok

      assert Tracing.with_span("cratis.chronicle.client.event_sequence.append", %{}, fn ->
               {:ok, "value"}
             end) == {:ok, "value"}
    end

    test "returns an {:error, _} result without raising" do
      assert Tracing.with_span("cratis.chronicle.client.event_sequence.append", %{}, fn ->
               {:error, :boom}
             end) == {:error, :boom}
    end

    test "accepts the full attribute set without error, including :kind" do
      attributes = %{
        "cratis.event_store.name" => "my-store",
        "cratis.event_store.namespace" => "default",
        "cratis.event_sequence.id" => "event-log",
        "cratis.event_type.id" => "it-account-opened",
        "cratis.correlation_id" => "00000000-0000-0000-0000-000000000000",
        kind: :client
      }

      assert Tracing.with_span("cratis.chronicle.client.event_sequence.append", attributes, fn ->
               :ok
             end) == :ok
    end

    test "records the exception on the span and re-raises it" do
      assert_raise RuntimeError, "kaboom", fn ->
        Tracing.with_span("cratis.chronicle.client.event_sequence.append", %{}, fn ->
          raise "kaboom"
        end)
      end
    end
  end

  describe "with_telemetry_span/5" do
    setup do
      ref = make_ref()
      test_pid = self()

      handler_id = "tracing-test-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:cratis, :chronicle, :client, :append, :start],
          [:cratis, :chronicle, :client, :append, :stop],
          [:cratis, :chronicle, :client, :append, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits :start and :stop around a successful call" do
      assert Tracing.with_telemetry_span(
               [:cratis, :chronicle, :client, :append],
               %{event_sequence_id: "event-log", event_count: 1},
               "cratis.chronicle.client.event_sequence.append",
               %{"cratis.event_sequence.id" => "event-log", kind: :client},
               fn -> :ok end
             ) == :ok

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :start], _,
                      %{event_sequence_id: "event-log", event_count: 1}}

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :stop], _,
                      stop_metadata}

      refute Map.has_key?(stop_metadata, :error)
    end

    test "flags :error in the :stop metadata for an {:error, _} result" do
      assert Tracing.with_telemetry_span(
               [:cratis, :chronicle, :client, :append],
               %{event_sequence_id: "event-log", event_count: 1},
               "cratis.chronicle.client.event_sequence.append",
               %{},
               fn -> {:error, :boom} end
             ) == {:error, :boom}

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :start], _, _}

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :stop], _,
                      stop_metadata}

      assert stop_metadata.error == true
    end

    test "emits :exception and re-raises when the function raises" do
      assert_raise RuntimeError, "kaboom", fn ->
        Tracing.with_telemetry_span(
          [:cratis, :chronicle, :client, :append],
          %{event_sequence_id: "event-log", event_count: 1},
          "cratis.chronicle.client.event_sequence.append",
          %{},
          fn -> raise "kaboom" end
        )
      end

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :start], _, _}

      assert_receive {:telemetry, [:cratis, :chronicle, :client, :append, :exception], _,
                      exception_metadata}

      assert exception_metadata.kind == :error
      assert %RuntimeError{} = exception_metadata.reason
    end
  end

  describe "trace_event_source_id?/0" do
    test "is off by default" do
      refute Tracing.trace_event_source_id?()
    end

    test "honors config :cratis_chronicle, :trace_event_source_id" do
      Application.put_env(:cratis_chronicle, :trace_event_source_id, true)

      on_exit(fn ->
        Application.delete_env(:cratis_chronicle, :trace_event_source_id)
      end)

      assert Tracing.trace_event_source_id?()
    end
  end
end
