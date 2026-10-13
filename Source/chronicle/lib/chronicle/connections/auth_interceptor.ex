# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AuthInterceptor do
  @moduledoc false

  # Attaches the authorization header to every outgoing RPC, fetched fresh
  # from `Chronicle.Connections.TokenProvider` at call time. Installing auth
  # per call rather than as channel headers means an expiring OAuth token
  # never invalidates the channel: streams opened while a token was valid
  # stay authenticated, and every new call carries a current token.

  @behaviour GRPC.Client.Interceptor

  alias Chronicle.Connections.TokenProvider

  @unauthenticated 16

  @impl GRPC.Client.Interceptor
  def init(opts), do: opts

  @impl GRPC.Client.Interceptor
  def call(stream, request, next, opts) do
    provider = Keyword.fetch!(opts, :provider)

    case send_with_token(stream, request, next, provider) do
      {:error, %GRPC.RPCError{status: @unauthenticated}} ->
        # The kernel refused the token (it may have restarted with new signing keys). Drop the
        # cached token and retry exactly once with a fresh one; a second refusal is a real
        # authentication failure and is returned as it is.
        TokenProvider.invalidate(provider)
        send_with_token(stream, request, next, provider)

      result ->
        result
    end
  end

  defp send_with_token(stream, request, next, provider) do
    headers = TokenProvider.authorization_headers(provider)
    next.(GRPC.Client.Stream.put_headers(stream, headers), request)
  end
end
