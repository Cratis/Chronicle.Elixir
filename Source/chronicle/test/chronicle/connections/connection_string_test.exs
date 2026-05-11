# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionStringTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.ConnectionString

  describe "default/0" do
    test "connects to localhost on port 35000" do
      cs = ConnectionString.default()
      assert cs.server_address.host == "localhost"
      assert cs.server_address.port == 35_000
    end

    test "has no authentication" do
      cs = ConnectionString.default()
      assert ConnectionString.authentication_mode(cs) == :none
    end
  end

  describe "development/0" do
    test "connects to localhost on port 35000" do
      cs = ConnectionString.development()
      assert cs.server_address.host == "localhost"
      assert cs.server_address.port == 35_000
    end

    test "uses client credentials" do
      cs = ConnectionString.development()
      assert ConnectionString.authentication_mode(cs) == :client_credentials
    end
  end

  describe "parse/1" do
    test "parses host and port" do
      cs = ConnectionString.parse("chronicle://myserver:9000")
      assert cs.server_address.host == "myserver"
      assert cs.server_address.port == 9000
    end

    test "defaults to port 35000 when omitted" do
      cs = ConnectionString.parse("chronicle://myserver")
      assert cs.server_address.port == 35_000
    end

    test "parses api key from query string" do
      cs = ConnectionString.parse("chronicle://localhost:35000?apiKey=my-secret")
      assert cs.api_key == "my-secret"
      assert ConnectionString.authentication_mode(cs) == :api_key
    end

    test "parses disableTls flag" do
      cs = ConnectionString.parse("chronicle://localhost:35000?disableTls=true")
      assert cs.disable_tls == true
    end

    test "parses client credentials from userinfo" do
      cs = ConnectionString.parse("chronicle://client-id:secret@localhost:35000")
      assert cs.username == "client-id"
      assert cs.password == "secret"
      assert ConnectionString.authentication_mode(cs) == :client_credentials
    end

    test "decodes URL-encoded credentials" do
      cs = ConnectionString.parse("chronicle://my%40client:p%40ss@localhost:35000")
      assert cs.username == "my@client"
      assert cs.password == "p@ss"
    end

    test "supports chronicle+srv scheme" do
      cs = ConnectionString.parse("chronicle+srv://my-service:35000")
      assert cs.scheme == "chronicle+srv"
    end

    test "raises on unsupported scheme" do
      assert_raise ArgumentError, ~r/Unsupported/, fn ->
        ConnectionString.parse("http://localhost:35000")
      end
    end

    test "raises on missing host" do
      assert_raise ArgumentError, fn ->
        ConnectionString.parse("chronicle://")
      end
    end

    test "raises on invalid port" do
      assert_raise ArgumentError, ~r/port/, fn ->
        ConnectionString.parse("chronicle://localhost:99999")
      end
    end
  end

  describe "format/1" do
    test "round-trips a simple connection string" do
      original = "chronicle://localhost:35000"
      assert ConnectionString.parse(original) |> ConnectionString.format() == original
    end

    test "round-trips a connection string with credentials" do
      original = "chronicle://client:secret@myserver:9000"
      assert ConnectionString.parse(original) |> ConnectionString.format() == original
    end

    test "round-trips a connection string with query parameters" do
      cs = ConnectionString.parse("chronicle://localhost:35000?apiKey=abc&disableTls=true")
      formatted = ConnectionString.format(cs)
      assert formatted =~ "apiKey=abc"
      assert formatted =~ "disableTls=true"
    end
  end

  describe "with_credentials/3" do
    test "adds credentials and removes api key" do
      cs =
        ConnectionString.parse("chronicle://localhost:35000?apiKey=old-key")
        |> ConnectionString.with_credentials("new-client", "new-secret")

      assert cs.username == "new-client"
      assert cs.password == "new-secret"
      assert is_nil(cs.api_key)
    end
  end

  describe "with_api_key/2" do
    test "adds api key and removes credentials" do
      cs =
        ConnectionString.parse("chronicle://user:pass@localhost:35000")
        |> ConnectionString.with_api_key("my-key")

      assert cs.api_key == "my-key"
      assert is_nil(cs.username)
      assert is_nil(cs.password)
    end
  end

  describe "String.Chars protocol" do
    test "formats via to_string/1" do
      cs = ConnectionString.parse("chronicle://localhost:35000")
      assert to_string(cs) == "chronicle://localhost:35000"
    end
  end
end
