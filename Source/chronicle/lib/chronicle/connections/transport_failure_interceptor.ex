# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TransportFailureInterceptor do
  @moduledoc false

  # Every Chronicle function promises `{:error, reason}` when a call fails. Two transport
  # failures in the gRPC transport break that promise, so they are turned into the error a refused
  # connection produces:
  #
  #   * A call racing a dying channel: the Mint adapter hands the request to its connection
  #     process with GenServer.call, and when that process has already stopped the call exits
  #     the caller.
  #   * A reply grpc can't read, such as the trailers-only response the kernel sends when it
  #     rejects an unauthenticated call, which raises inside grpc.
  #
  # Exceptions raised outside grpc, such as a protobuf encoding error or a bug in another
  # interceptor, are re-raised unchanged. Installed as the last interceptor, which grpc-elixir
  # makes the outermost one.
  #
  # Before the request reaches the connection, the adapter starts a response process for the
  # call and links it to the caller. A call that fails - it exits, raises, or returns an error
  # because the connection was already closed - leaves that process with nobody to read it, so
  # it is stopped here (see Chronicle.Connections.ResponseProcesses). A call that succeeds hands
  # its responses to the caller, and the process stops once they are read.

  @behaviour GRPC.Client.Interceptor

  alias Chronicle.Connections.ResponseProcesses

  @impl GRPC.Client.Interceptor
  def init(opts), do: opts

  @impl GRPC.Client.Interceptor
  def call(stream, request, next, _opts) do
    snapshot = ResponseProcesses.snapshot()

    try do
      case next.(stream, request) do
        {:error, _reason} = error ->
          release(snapshot)
          error

        {:error, _reason, _headers} = error ->
          release(snapshot)
          error

        result ->
          result
      end
    rescue
      error ->
        release(snapshot)

        if raised_in_grpc?(__STACKTRACE__) do
          {:error,
           GRPC.RPCError.exception(
             GRPC.Status.internal(),
             "Chronicle call failed in the gRPC transport: #{Exception.message(error)}"
           )}
        else
          reraise error, __STACKTRACE__
        end
    catch
      :exit, reason ->
        release(snapshot)

        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.unavailable(),
           "Chronicle connection is not available: #{inspect(reason, limit: 5)}"
         )}
    end
  end

  defp release(snapshot),
    do: snapshot |> ResponseProcesses.started_since() |> ResponseProcesses.stop()

  # The raising frame is often a standard library function (Keyword.fetch!/2) called by grpc, so
  # the first frame outside Elixir's and Erlang's standard libraries decides who raised.
  @standard_applications [:elixir, :stdlib, :kernel, :logger, :telemetry]
  @transport_applications [:grpc, :grpc_core, :mint]

  defp raised_in_grpc?(stacktrace) do
    stacktrace
    |> Enum.map(fn {module, _function, _arity, _location} -> application(module) end)
    |> Enum.find(&(&1 not in @standard_applications))
    |> Kernel.in(@transport_applications)
  end

  defp application(module) do
    case :application.get_application(module) do
      {:ok, application} -> application
      :undefined -> nil
    end
  end
end
