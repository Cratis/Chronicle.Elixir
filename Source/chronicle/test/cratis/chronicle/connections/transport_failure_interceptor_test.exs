# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Connections.TransportFailureInterceptorTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Connections.TransportFailureInterceptor
  alias GRPC.Client.Adapters.Mint.StreamResponseProcess

  defp call(next), do: TransportFailureInterceptor.call(%GRPC.Client.Stream{}, :request, next, [])

  defp dead_process do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    pid
  end

  test "passes the result of a working call through unchanged" do
    assert call(fn _stream, request -> {:ok, request} end) == {:ok, :request}
  end

  test "turns an exit from a dead connection process into an unavailable error" do
    dead = dead_process()

    assert {:error, %GRPC.RPCError{status: status, message: message}} =
             call(fn _stream, _request -> GenServer.call(dead, :request) end)

    assert status == GRPC.Status.unavailable()
    assert message =~ "not available"
  end

  test "stops the response process the adapter started for a call that exited" do
    dead = dead_process()
    test_pid = self()

    call(fn stream, _request ->
      {:ok, response_process} = StreamResponseProcess.start_link(stream, false)
      send(test_pid, {:response_process, response_process})
      GenServer.call(dead, :request)
    end)

    assert_receive {:response_process, response_process}
    refute Process.alive?(response_process)
    {:links, links} = Process.info(self(), :links)
    refute response_process in links
  end

  test "stops the response process of a call that returned an error on a closed connection" do
    error =
      {:error,
       GRPC.RPCError.exception(
         GRPC.Status.unknown(),
         "error occurred while receiving data: {:error, \"the connection is closed\"}"
       )}

    response_process = response_process_of(fn -> error end)

    assert_stopped(response_process)
  end

  test "stops the response process of a call that raised" do
    response_process =
      response_process_of(fn -> GRPC.RPCError.exception(:no_such_status, "x") end)

    assert_stopped(response_process)
  end

  test "leaves the response process of a stream that opened to its reader" do
    response_process = response_process_of(fn -> {:ok, :reply_stream} end)

    assert Process.alive?(response_process)
    {:links, links} = Process.info(self(), :links)
    assert response_process in links
  end

  test "turns a raise inside grpc into an internal error" do
    assert {:error, %GRPC.RPCError{status: status, message: message}} =
             call(fn _stream, _request -> GRPC.RPCError.exception(:no_such_status, "x") end)

    assert status == GRPC.Status.internal()
    assert message =~ "gRPC transport"
  end

  test "re-raises an exception raised outside grpc" do
    assert_raise KeyError, fn ->
      call(fn _stream, _request -> Keyword.fetch!([], :ok) end)
    end
  end

  # Runs a call that starts a response process the way the Mint adapter does, then ends with `outcome`.
  defp response_process_of(outcome) do
    test_pid = self()

    call(fn stream, _request ->
      {:ok, response_process} = StreamResponseProcess.start_link(stream, false)
      send(test_pid, {:response_process, response_process})
      outcome.()
    end)

    assert_receive {:response_process, response_process}
    response_process
  end

  defp assert_stopped(response_process) do
    ref = Process.monitor(response_process)
    assert_receive {:DOWN, ^ref, :process, ^response_process, _}, 1_000
    {:links, links} = Process.info(self(), :links)
    refute response_process in links
  end
end
