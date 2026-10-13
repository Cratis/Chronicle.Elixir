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

  describe "unauthenticated responses" do
    defp counting_provider do
      counter = :counters.new(1, [])

      {:ok, provider} =
        TokenProvider.start_link(
          connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
          fetch_fun: fn _ ->
            :counters.add(counter, 1, 1)
            {:ok, {"token-#{:counters.get(counter, 1)}", 3_600}}
          end
        )

      {provider, counter}
    end

    test "refetches the token and retries exactly once" do
      {provider, counter} = counting_provider()
      opts = AuthInterceptor.init(provider: provider)
      stream = %GRPC.Client.Stream{}
      test = self()

      next = fn stream_out, _request ->
        auth = stream_out.headers["authorization"]
        send(test, {:sent, auth})

        if auth == "Bearer token-1",
          do: {:error, GRPC.RPCError.exception(GRPC.Status.unauthenticated(), "expired")},
          else: {:ok, :reply}
      end

      assert AuthInterceptor.call(stream, :request, next, opts) == {:ok, :reply}
      assert_received {:sent, "Bearer token-1"}
      assert_received {:sent, "Bearer token-2"}
      assert :counters.get(counter, 1) == 2
    end

    test "a second refusal is returned, not retried again" do
      {provider, _counter} = counting_provider()
      opts = AuthInterceptor.init(provider: provider)
      test = self()

      next = fn _stream, _request ->
        send(test, :sent)
        {:error, GRPC.RPCError.exception(GRPC.Status.unauthenticated(), "nope")}
      end

      assert {:error, %GRPC.RPCError{status: 16}} =
               AuthInterceptor.call(%GRPC.Client.Stream{}, :request, next, opts)

      assert_received :sent
      assert_received :sent
      refute_received :sent
    end

    test "other errors are not retried" do
      {provider, _counter} = counting_provider()
      opts = AuthInterceptor.init(provider: provider)
      test = self()

      next = fn _stream, _request ->
        send(test, :sent)
        {:error, GRPC.RPCError.exception(GRPC.Status.unavailable(), "down")}
      end

      assert {:error, %GRPC.RPCError{status: 14}} =
               AuthInterceptor.call(%GRPC.Client.Stream{}, :request, next, opts)

      assert_received :sent
      refute_received :sent
    end
  end

  test "invalidating a provider forces the next call to fetch again" do
    {:ok, provider} =
      TokenProvider.start_link(
        connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
        fetch_fun: fn _ -> {:ok, {"t-#{System.unique_integer([:positive])}", 3_600}} end
      )

    first = TokenProvider.authorization_headers(provider)
    assert TokenProvider.authorization_headers(provider) == first
    TokenProvider.invalidate(provider)
    refute TokenProvider.authorization_headers(provider) == first
  end
end
