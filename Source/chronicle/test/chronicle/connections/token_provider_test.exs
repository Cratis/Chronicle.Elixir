# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TokenProviderTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.{ConnectionString, TokenProvider}

  # Long enough to stay outside the 60s refresh margin for the whole test.
  @long_lifetime 3_600
  # Short enough to be inside the refresh margin immediately.
  @short_lifetime 30

  defp start(responses) do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    fetch_fun = fn _connection_string ->
      call = Agent.get_and_update(calls, fn n -> {n, n + 1} end)
      # The last configured response repeats for any further calls.
      Enum.at(responses, call, List.last(responses))
    end

    {:ok, provider} =
      TokenProvider.start_link(
        connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
        fetch_fun: fetch_fun
      )

    {provider, calls}
  end

  defp fetch_count(calls), do: Agent.get(calls, & &1)

  test "fetches a token on first use and returns bearer headers" do
    {provider, calls} = start([{:ok, {"token-1", @long_lifetime}}])

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    assert fetch_count(calls) == 1
  end

  test "serves the cached token while it is fresh" do
    {provider, calls} = start([{:ok, {"token-1", @long_lifetime}}, {:ok, {"token-2", @long_lifetime}}])

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    assert fetch_count(calls) == 1
  end

  test "defaults the lifetime when the token response has no expires_in" do
    {provider, calls} = start([{:ok, {"token-1", nil}}])

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    assert fetch_count(calls) == 1
  end

  test "refreshes ahead of expiry once inside the refresh margin" do
    {provider, calls} =
      start([{:ok, {"token-1", @short_lifetime}}, {:ok, {"token-2", @short_lifetime}}])

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    # The short lifetime is already inside the margin, so the next request
    # refreshes even though the first token has not expired yet.
    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-2"}

    assert fetch_count(calls) == 2
  end

  @tag capture_log: true
  test "keeps serving the cached token when a refresh fails before expiry" do
    {provider, _calls} =
      start([{:ok, {"token-1", @short_lifetime}}, {:error, :unavailable}])

    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}

    # Refresh is due (inside the margin) and fails — the token is still valid
    # for another 30s, so it must keep flowing rather than dropping auth.
    assert TokenProvider.authorization_headers(provider) ==
             %{"authorization" => "Bearer token-1"}
  end

  @tag capture_log: true
  test "returns no headers when no token can be fetched" do
    {provider, _calls} = start([{:error, :unavailable}])

    assert TokenProvider.authorization_headers(provider) == %{}
  end

  @tag capture_log: true
  test "throttles fetch attempts after a failure" do
    {provider, calls} = start([{:error, :unavailable}])

    assert TokenProvider.authorization_headers(provider) == %{}
    assert TokenProvider.authorization_headers(provider) == %{}

    # The second request arrives well inside the retry delay — one attempt,
    # not one per RPC (the session answers a keepalive every second).
    assert fetch_count(calls) == 1
  end
end
