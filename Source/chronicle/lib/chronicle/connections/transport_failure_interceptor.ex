# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TransportFailureInterceptor do
  @moduledoc false

  # A call can race a channel that is dying: the gRPC adapter hands the request to its
  # connection process with GenServer.call, and when that process has already stopped the
  # call exits the caller instead of returning. Every Chronicle function promises
  # `{:error, reason}` for a failed call, so the exit is turned into the same
  # `%GRPC.RPCError{status: unavailable}` a refused connection produces. The session
  # watchdog independently notices the dead channel and reconnects.
  #
  # Installed as the last interceptor, which grpc-elixir makes the outermost one, so it
  # covers the transport and every other interceptor.

  @behaviour GRPC.Client.Interceptor

  @impl GRPC.Client.Interceptor
  def init(opts), do: opts

  @impl GRPC.Client.Interceptor
  def call(stream, request, next, _opts) do
    next.(stream, request)
  rescue
    # grpc 0.11 can raise while reading a reply it doesn't expect, such as the trailers-only
    # response the kernel sends when it rejects an unauthenticated call. Report it like any
    # other failed call instead of crashing the caller.
    error ->
      {:error,
       GRPC.RPCError.exception(
         GRPC.Status.internal(),
         "Chronicle call failed in the gRPC transport: #{Exception.message(error)}"
       )}
  catch
    :exit, reason ->
      {:error,
       GRPC.RPCError.exception(
         GRPC.Status.unavailable(),
         "Chronicle connection is not available: #{inspect(reason, limit: 5)}"
       )}
  end
end
