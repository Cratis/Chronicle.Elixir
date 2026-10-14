# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TracePropagationInterceptorTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.TracePropagationInterceptor
  alias OpenTelemetry.Tracer

  setup do
    previous_injector = :opentelemetry.get_text_map_injector()

    on_exit(fn ->
      :opentelemetry.set_text_map_injector(previous_injector)
      Tracer.set_current_span(:undefined)
    end)

    :ok
  end

  defp next_capturing_headers do
    fn stream_out, request -> {stream_out.headers, request} end
  end

  test "injects no trace header when no OpenTelemetry SDK is installed (the default no-op propagator)" do
    stream = %GRPC.Client.Stream{}

    assert {%{}, :request} =
             TracePropagationInterceptor.call(stream, :request, next_capturing_headers(), [])
  end

  test "injects no trace header when a propagator is configured but no span context is active" do
    :opentelemetry.set_text_map_injector(:otel_propagator_trace_context)
    stream = %GRPC.Client.Stream{}

    assert {%{}, :request} =
             TracePropagationInterceptor.call(stream, :request, next_capturing_headers(), [])
  end

  test "injects traceparent for the active span context when a propagator is configured" do
    :opentelemetry.set_text_map_injector(:otel_propagator_trace_context)
    span_ctx = :otel_tracer.from_remote_span(0x1234, 0x5678, 1)
    Tracer.set_current_span(span_ctx)

    stream = %GRPC.Client.Stream{}

    assert {headers, :request} =
             TracePropagationInterceptor.call(stream, :request, next_capturing_headers(), [])

    assert headers["traceparent"] ==
             "00-00000000000000000000000000001234-0000000000005678-01"
  end

  test "merges the injected header alongside headers already on the stream" do
    :opentelemetry.set_text_map_injector(:otel_propagator_trace_context)
    span_ctx = :otel_tracer.from_remote_span(0x1234, 0x5678, 1)
    Tracer.set_current_span(span_ctx)

    stream = %GRPC.Client.Stream{headers: %{"api-key" => "secret"}}

    assert {headers, :request} =
             TracePropagationInterceptor.call(stream, :request, next_capturing_headers(), [])

    assert headers["api-key"] == "secret"
    assert Map.has_key?(headers, "traceparent")
  end
end
