# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Diagnostics.Tracing do
  @moduledoc """
  OpenTelemetry span helper for the Chronicle Elixir client.

  Every span created through `with_span/3` uses the `Cratis.Chronicle.Client`
  instrumentation scope, per the shared Cratis OpenTelemetry convention
  (`Cratis/Architecture#33`). The convention is the same string in every
  Chronicle client language, so a collector groups them together regardless
  of which language produced a given span.

  This module depends only on `opentelemetry_api`: with no OpenTelemetry SDK
  installed in the host application, every call here is a documented no-op —
  there is no Chronicle-specific "enable tracing" switch, matching the
  convention's instrumentation-is-always-on default.

  See `Documentation/observability.md` for the full span and attribute
  reference.
  """

  alias OpenTelemetry.Span

  @scope "Cratis.Chronicle.Client"

  @type attributes :: %{optional(String.t()) => String.t() | integer() | float() | boolean()}
  @type span_kind :: :internal | :client | :server | :producer | :consumer

  @doc """
  Runs `fun` inside a new span named `name`, in the `Cratis.Chronicle.Client`
  instrumentation scope.

  `attributes` is a map of string keys to span attributes, set before `fun`
  runs (see the attribute registry in `Documentation/observability.md`).
  `:kind` is an optional key in `attributes` giving the `t:span_kind/0`
  (default `:internal`); it is not itself set as a span attribute.

  An exception raised by `fun` is recorded on the span as an `exception` event
  carrying only `exception.type` (the module), the span status is set to error
  with the module name as description, and the exception is re-raised — this
  never swallows a failure. A `fun` that returns `{:error, _}` sets the span
  status to error without raising, with the first atom of the error tuple as
  description. Messages, reasons and stacktraces are never recorded because
  they can carry event payloads or unique values.
  """
  @spec with_span(String.t(), attributes(), (-> result)) :: result when result: var
  def with_span(name, attributes \\ %{}, fun) when is_function(fun, 0) do
    kind = Map.get(attributes, :kind, :internal)
    span_attributes = Map.delete(attributes, :kind)

    :otel_tracer.with_span(tracer(), name, %{kind: kind}, fn span_ctx ->
      Span.set_attributes(span_ctx, Map.to_list(span_attributes))

      try do
        case fun.() do
          {:error, reason} = error ->
            Span.set_status(span_ctx, OpenTelemetry.status(:error, classify(reason)))
            error

          other ->
            other
        end
      rescue
        exception ->
          type = inspect(exception.__struct__)
          Span.add_event(span_ctx, "exception", %{"exception.type" => type})
          Span.set_status(span_ctx, OpenTelemetry.status(:error, type))

          reraise exception, __STACKTRACE__
      end
    end)
  end

  @doc """
  Runs `fun` inside both a `:telemetry` span and an OpenTelemetry span.

  `telemetry_event` and `telemetry_metadata` are passed to `:telemetry.span/3`,
  which emits `:start`, `:stop`, and `:exception` events under that prefix —
  for applications that build metrics on `:telemetry` rather than an
  OpenTelemetry metrics exporter. `span_name` and `span_attributes` are passed
  to `with_span/3` as usual. An exception raised by `fun` is recorded and
  re-raised by `with_span/3` first, then observed and re-raised again by
  `:telemetry.span/3` — both see it, and it still reaches the caller.
  """
  @spec with_telemetry_span(
          [atom(), ...],
          map(),
          String.t(),
          attributes(),
          (-> result)
        ) :: result
        when result: var
  def with_telemetry_span(telemetry_event, telemetry_metadata, span_name, span_attributes, fun) do
    :telemetry.span(telemetry_event, telemetry_metadata, fn ->
      case with_span(span_name, span_attributes, fun) do
        {:error, _} = error -> {error, Map.put(telemetry_metadata, :error, true)}
        other -> {other, telemetry_metadata}
      end
    end)
  end

  @doc """
  Whether `cratis.event_source.id` may be set on spans.

  Off by default, per the shared convention's PII guidance (D7): an event
  source id can itself be sensitive. Enable it with
  `config :cratis_chronicle, trace_event_source_id: true`.
  """
  @spec trace_event_source_id?() :: boolean()
  def trace_event_source_id? do
    Application.get_env(:cratis_chronicle, :trace_event_source_id, false)
  end

  defp tracer do
    version = Application.spec(:cratis_chronicle, :vsn)
    OpenTelemetry.get_tracer(@scope, version && to_string(version), "")
  end

  # Only a fixed classification is ever put on a span: reasons and exception
  # messages can carry event payloads, unique values and models.
  @doc false
  @spec classify(term()) :: String.t()
  def classify(%module{}), do: inspect(module)

  def classify(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      tag when is_atom(tag) -> Atom.to_string(tag)
      _ -> "error"
    end
  end

  def classify(reason) when is_atom(reason), do: Atom.to_string(reason)
  def classify(_reason), do: "error"
end
