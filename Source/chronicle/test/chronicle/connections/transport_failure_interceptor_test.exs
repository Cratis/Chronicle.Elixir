# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TransportFailureInterceptorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.TransportFailureInterceptor

  test "passes the result of a working call through unchanged" do
    next = fn _stream, request -> {:ok, request} end

    assert TransportFailureInterceptor.call(%GRPC.Client.Stream{}, :request, next, []) ==
             {:ok, :request}
  end

  test "turns an exit from a dead connection process into an unavailable error" do
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}

    next = fn _stream, _request -> GenServer.call(dead, :request) end

    assert {:error, %GRPC.RPCError{status: status, message: message}} =
             TransportFailureInterceptor.call(%GRPC.Client.Stream{}, :request, next, [])

    assert status == GRPC.Status.unavailable()
    assert message =~ "not available"
  end

  test "turns a raise inside the transport into an internal error" do
    next = fn _stream, _request -> Keyword.fetch!([], :ok) end

    assert {:error, %GRPC.RPCError{status: status, message: message}} =
             TransportFailureInterceptor.call(%GRPC.Client.Stream{}, :request, next, [])

    assert status == GRPC.Status.internal()
    assert message =~ "key :ok not found"
  end
end
