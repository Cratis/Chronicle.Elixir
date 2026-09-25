# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TransportFailureInterceptorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.TransportFailureInterceptor
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
end
