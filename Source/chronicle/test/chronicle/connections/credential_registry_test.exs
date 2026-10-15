# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CredentialRegistryTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.{Connection, ConnectionString, CredentialRegistry, TokenProvider}

  @secret "scrubber-secret-value"

  setup do
    on_exit(fn -> CredentialRegistry.forget(@secret) end)
  end

  test "remembers long values once and ignores short or non-binary ones" do
    :ok = CredentialRegistry.remember(@secret)
    :ok = CredentialRegistry.remember(@secret)
    :ok = CredentialRegistry.remember("short")
    :ok = CredentialRegistry.remember(nil)

    assert Enum.count(CredentialRegistry.values(), &(&1 == @secret)) == 1
    refute "short" in CredentialRegistry.values()
  end

  test "keeps only the newest values so rotating tokens cannot grow it" do
    tokens = for n <- 1..40, do: "rotating-token-#{n}-padding"
    Enum.each(tokens, &CredentialRegistry.remember/1)
    on_exit(fn -> Enum.each(tokens, &CredentialRegistry.forget/1) end)

    assert length(CredentialRegistry.values()) <= 16
    assert List.last(tokens) in CredentialRegistry.values()
  end

  test "a connection remembers its API key and a fetched token is remembered" do
    api_key = "connection-api-key-#{System.unique_integer([:positive])}"
    token = "fetched-oauth-token-#{System.unique_integer([:positive])}"
    on_exit(fn -> Enum.each([api_key, token], &CredentialRegistry.forget/1) end)

    {:ok, connection} =
      Connection.start_link(
        connection_string: "chronicle://localhost:35000?apiKey=#{api_key}&disableTls=true",
        auto_connect: false
      )

    assert api_key in CredentialRegistry.values()

    {:ok, provider} =
      TokenProvider.start_link(
        connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
        fetch_fun: fn _ -> {:ok, {token, 3_600}} end
      )

    TokenProvider.authorization_headers(provider)
    assert token in CredentialRegistry.values()
    GenServer.stop(connection)
  end
end
