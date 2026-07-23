# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AuthInterceptorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{AuthInterceptor, ConnectionString, TokenProvider}

  defp start_provider(fetch_result) do
    {:ok, provider} =
      TokenProvider.start_link(
        connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
        fetch_fun: fn _connection_string -> fetch_result end
      )

    provider
  end

  test "attaches a fresh bearer token to the outgoing stream" do
    provider = start_provider({:ok, {"token-1", 3_600}})
    opts = AuthInterceptor.init(provider: provider)
    stream = %GRPC.Client.Stream{}

    next = fn stream_out, request ->
      {stream_out.headers, request}
    end

    assert AuthInterceptor.call(stream, :request, next, opts) ==
             {%{"authorization" => "Bearer token-1"}, :request}
  end

  @tag capture_log: true
  test "leaves the stream without auth headers when no token is available" do
    provider = start_provider({:error, :unavailable})
    opts = AuthInterceptor.init(provider: provider)
    stream = %GRPC.Client.Stream{}

    next = fn stream_out, request ->
      {stream_out.headers, request}
    end

    # The RPC proceeds and fails with the server's auth rejection — that is
    # the session machinery's problem, not the interceptor's.
    assert AuthInterceptor.call(stream, :request, next, opts) == {%{}, :request}
  end
end
