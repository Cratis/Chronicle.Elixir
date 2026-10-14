# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TracePropagationInterceptor do
  @moduledoc false

  # Injects the W3C traceparent/tracestate headers for the OpenTelemetry span
  # active in the calling process (if any) into every outbound gRPC call, so a
  # trace that started in the application continues into the Chronicle kernel.
  #
  # Always installed, per the shared Cratis OpenTelemetry convention
  # (Cratis/Architecture#33, D5): every process hop Cratis owns injects and
  # extracts trace context explicitly rather than relying on host
  # auto-instrumentation. With no OpenTelemetry SDK installed, the default
  # text-map injector is a no-op and this adds no headers.

  @behaviour GRPC.Client.Interceptor

  @impl GRPC.Client.Interceptor
  def init(opts), do: opts

  @impl GRPC.Client.Interceptor
  def call(stream, request, next, _opts) do
    case :otel_propagator_text_map.inject([]) do
      [] -> next.(stream, request)
      headers -> next.(GRPC.Client.Stream.put_headers(stream, Map.new(headers)), request)
    end
  end
end
