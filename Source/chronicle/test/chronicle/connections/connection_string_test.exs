# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionStringTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.ConnectionString

  describe "default/0" do
    test "connects to localhost on port 35000" do
      cs = ConnectionString.default()
      assert ConnectionString.server_address(cs).host == "localhost"
      assert ConnectionString.server_address(cs).port == 35_000
    end

    test "has no authentication" do
      cs = ConnectionString.default()
      assert ConnectionString.authentication_mode(cs) == :none
    end
  end

  describe "development/0" do
    test "connects to localhost on port 35000" do
      cs = ConnectionString.development()
      assert ConnectionString.server_address(cs).host == "localhost"
      assert ConnectionString.server_address(cs).port == 35_000
    end

    test "uses client credentials" do
      cs = ConnectionString.development()
      assert ConnectionString.authentication_mode(cs) == :client_credentials
    end
  end

  describe "parse/1" do
    test "parses host and port" do
      cs = ConnectionString.parse("chronicle://myserver:9000")
      assert ConnectionString.server_address(cs).host == "myserver"
      assert ConnectionString.server_address(cs).port == 9000
    end

    test "defaults to port 35000 when omitted" do
      cs = ConnectionString.parse("chronicle://myserver")
      assert ConnectionString.server_address(cs).port == 35_000
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

    test "raises when a scheme is entirely missing" do
      assert_raise ArgumentError, ~r/scheme/, fn ->
        ConnectionString.parse("localhost:35000")
      end
    end
  end

  describe "parse/1 with multiple hosts" do
    test "parses a comma-separated host list" do
      cs = ConnectionString.parse("chronicle://host1:1000,host2:2000")

      assert cs.server_addresses == [
               %ConnectionString.ServerAddress{host: "host1", port: 1000},
               %ConnectionString.ServerAddress{host: "host2", port: 2000}
             ]
    end

    test "defaults the port per-host when omitted" do
      cs = ConnectionString.parse("chronicle://host1,host2:2000")

      assert cs.server_addresses == [
               %ConnectionString.ServerAddress{host: "host1", port: 35_000},
               %ConnectionString.ServerAddress{host: "host2", port: 2000}
             ]
    end

    test "parses credentials shared across every host" do
      cs = ConnectionString.parse("chronicle://user:pass@host1:1000,host2:2000")

      assert cs.username == "user"
      assert cs.password == "pass"
      assert length(cs.server_addresses) == 2
    end

    test "parses query parameters after a multi-host list" do
      cs = ConnectionString.parse("chronicle://host1:1000,host2:2000?apiKey=my-key")

      assert length(cs.server_addresses) == 2
      assert cs.api_key == "my-key"
    end

    test "server_address/1 returns the first configured host" do
      cs = ConnectionString.parse("chronicle://host1:1000,host2:2000")

      assert ConnectionString.server_address(cs) == %ConnectionString.ServerAddress{
               host: "host1",
               port: 1000
             }
    end
  end

  describe "parse/1 with IPv6 hosts" do
    test "parses a bracketed IPv6 host with a port" do
      cs = ConnectionString.parse("chronicle://[::1]:9000")

      assert ConnectionString.server_address(cs) == %ConnectionString.ServerAddress{
               host: "::1",
               port: 9000
             }
    end

    test "defaults the port for a bracketed IPv6 host without one" do
      cs = ConnectionString.parse("chronicle://[::1]")

      assert ConnectionString.server_address(cs) == %ConnectionString.ServerAddress{
               host: "::1",
               port: 35_000
             }
    end

    test "parses multiple bracketed IPv6 hosts" do
      cs = ConnectionString.parse("chronicle://[2001:db8::1]:1000,[2001:db8::2]:2000")

      assert cs.server_addresses == [
               %ConnectionString.ServerAddress{host: "2001:db8::1", port: 1000},
               %ConnectionString.ServerAddress{host: "2001:db8::2", port: 2000}
             ]
    end

    test "parses a bare (unbracketed) IPv6 host without a port" do
      cs = ConnectionString.parse("chronicle://::1")

      assert ConnectionString.server_address(cs) == %ConnectionString.ServerAddress{
               host: "::1",
               port: 35_000
             }
    end
  end

  describe "parse/1 with chronicle+srv" do
    test "supports chronicle+srv scheme" do
      cs = ConnectionString.parse("chronicle+srv://my-service:35000")
      assert cs.scheme == "chronicle+srv"
    end

    test "resolves to a single server address" do
      cs = ConnectionString.parse("chronicle+srv://my-service")

      assert cs.server_addresses == [
               %ConnectionString.ServerAddress{host: "my-service", port: 35_000}
             ]
    end

    test "raises when given more than one host" do
      assert_raise ArgumentError, ~r/single host/, fn ->
        ConnectionString.parse("chronicle+srv://host1,host2")
      end
    end

    test "parses srvNameServer" do
      cs = ConnectionString.parse("chronicle+srv://my-service?srvNameServer=1.1.1.1:53")
      assert cs.srv_name_server == "1.1.1.1:53"
    end

    test "srvNameServer defaults to nil" do
      cs = ConnectionString.parse("chronicle+srv://my-service")
      assert cs.srv_name_server == nil
    end
  end

  describe "parse/1 skipTlsValidation" do
    test "defaults to false" do
      cs = ConnectionString.parse("chronicle://localhost:35000")
      assert cs.skip_tls_validation == false
    end

    test "parses skipTlsValidation=true" do
      cs = ConnectionString.parse("chronicle://localhost:35000?skipTlsValidation=true")
      assert cs.skip_tls_validation == true
    end

    test "is independent from disableTls" do
      cs = ConnectionString.parse("chronicle://localhost:35000?skipTlsValidation=true")
      assert cs.disable_tls == false
    end
  end

  describe "parse/1 loadBalancer" do
    test "defaults to least_connections" do
      cs = ConnectionString.parse("chronicle://host1:1000,host2:2000")
      assert cs.load_balancer == :least_connections
    end

    test "parses least-connections explicitly" do
      cs = ConnectionString.parse("chronicle://host1:1000?loadBalancer=least-connections")
      assert cs.load_balancer == :least_connections
    end

    test "parses round-robin" do
      cs = ConnectionString.parse("chronicle://host1:1000?loadBalancer=round-robin")
      assert cs.load_balancer == :round_robin
    end

    test "parses random" do
      cs = ConnectionString.parse("chronicle://host1:1000?loadBalancer=random")
      assert cs.load_balancer == :random
    end

    test "raises on an unsupported strategy" do
      assert_raise ArgumentError, ~r/loadBalancer/, fn ->
        ConnectionString.parse("chronicle://host1:1000?loadBalancer=weighted")
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

    test "round-trips a multi-host connection string" do
      original = "chronicle://host1:1000,host2:2000,host3:3000"
      assert ConnectionString.parse(original) |> ConnectionString.format() == original
    end

    test "round-trips IPv6 hosts with bracket notation" do
      original = "chronicle://[::1]:1000,[2001:db8::2]:2000"
      assert ConnectionString.parse(original) |> ConnectionString.format() == original
    end

    test "round-trips skipTlsValidation, loadBalancer, and srvNameServer" do
      cs =
        ConnectionString.parse(
          "chronicle+srv://my-service?loadBalancer=round-robin&skipTlsValidation=true&srvNameServer=1.1.1.1"
        )

      formatted = ConnectionString.format(cs)
      assert formatted =~ "loadBalancer=round-robin"
      assert formatted =~ "skipTlsValidation=true"
      assert formatted =~ "srvNameServer=1.1.1.1"
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
