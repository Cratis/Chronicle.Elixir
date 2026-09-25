# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TransportFailureInterceptor do
  @moduledoc false

  # Every Chronicle function promises `{:error, reason}` when a call fails. Two transport
  # failures in grpc 0.11 break that promise, so they are turned into the error a refused
  # connection produces:
  #
  #   * A call racing a dying channel: the Mint adapter hands the request to its connection
  #     process with GenServer.call, and when that process has already stopped the call exits
  #     the caller. The adapter has already started, and linked to the caller, a response
  #     process for the call; nothing would ever reply to it, so it is stopped here.
  #   * A reply grpc can't read, such as the trailers-only response the kernel sends when it
  #     rejects an unauthenticated call, which raises inside grpc.
  #
  # Exceptions raised outside grpc, such as a protobuf encoding error or a bug in another
  # interceptor, are re-raised unchanged. Installed as the last interceptor, which grpc-elixir
  # makes the outermost one.

  @behaviour GRPC.Client.Interceptor

  @response_process GRPC.Client.Adapters.Mint.StreamResponseProcess

  @impl GRPC.Client.Interceptor
  def init(opts), do: opts

  @impl GRPC.Client.Interceptor
  def call(stream, request, next, _opts) do
    links_before = links()

    try do
      next.(stream, request)
    rescue
      error ->
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
        stop_orphaned_response_processes(links_before)

        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.unavailable(),
           "Chronicle connection is not available: #{inspect(reason, limit: 5)}"
         )}
    end
  end

  # The raising frame is often a standard library function (Keyword.fetch!/2) called by grpc, so
  # the first frame outside Elixir's and Erlang's standard libraries decides who raised.
  @standard_applications [:elixir, :stdlib, :kernel, :logger, :telemetry]
  @transport_applications [:grpc, :mint]

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

  defp links do
    {:links, links} = Process.info(self(), :links)
    MapSet.new(links)
  end

  defp stop_orphaned_response_processes(links_before) do
    links()
    |> MapSet.difference(links_before)
    |> Enum.filter(&(is_pid(&1) and response_process?(&1)))
    |> Enum.each(fn pid ->
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end)
  end

  defp response_process?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        match?({@response_process, _, _}, Keyword.get(dictionary, :"$initial_call"))

      nil ->
        false
    end
  end
end
