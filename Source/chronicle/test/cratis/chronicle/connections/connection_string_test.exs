# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Connections.ConnectionStringTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Connections.ConnectionString

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
    test "defaults to true" do
      cs = ConnectionString.parse("chronicle://localhost:35000")
      assert cs.skip_tls_validation == true
    end

    test "parses skipTlsValidation=false" do
      cs = ConnectionString.parse("chronicle://localhost:35000?skipTlsValidation=false")
      assert cs.skip_tls_validation == false
    end

    test "is independent from disableTls" do
      cs = ConnectionString.parse("chronicle://localhost:35000?skipTlsValidation=false")
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

  describe "parse/1 caCertificatePath" do
    test "defaults to nil" do
      assert ConnectionString.parse("chronicle://server:35000").ca_certificate_path == nil
    end

    test "parses the path" do
      cs = ConnectionString.parse("chronicle://server:35000?caCertificatePath=%2Fetc%2Fca.pem")
      assert cs.ca_certificate_path == "/etc/ca.pem"
    end

    test "may hold an at sign" do
      cs =
        ConnectionString.parse(
          "chronicle://server:35000?caCertificatePath=%2Fhome%2Fme@corp%2Fca.pem"
        )

      assert cs.ca_certificate_path == "/home/me@corp/ca.pem"
    end
  end

  describe "parse/1 auth" do
    test "auth=none disables authentication" do
      cs = ConnectionString.parse("chronicle://server:35000?auth=none")
      assert cs.no_authentication
      assert ConnectionString.authentication_mode(cs) == :none
    end

    test "is case-insensitive in key and value" do
      assert ConnectionString.parse("chronicle://server:35000?AUTH=None").no_authentication
    end

    test "beats credentials and an API key in the same connection string" do
      with_credentials = ConnectionString.parse("chronicle://user:pass@server:35000?auth=none")
      with_api_key = ConnectionString.parse("chronicle://server:35000?auth=none&apiKey=abc")
      assert ConnectionString.authentication_mode(with_credentials) == :none
      assert ConnectionString.authentication_mode(with_api_key) == :none
    end

    test "defaults to false" do
      refute ConnectionString.parse("chronicle://server:35000").no_authentication
    end

    test "with_credentials/3 and with_api_key/2 switch it off again" do
      cs = ConnectionString.parse("chronicle://server:35000?auth=none")
      refute ConnectionString.with_credentials(cs, "u", "p").no_authentication
      refute ConnectionString.with_api_key(cs, "k").no_authentication
    end
  end

  describe "parse/1 skipCompatibilityCheck and skipKeepAlive" do
    test "both default to false" do
      cs = ConnectionString.parse("chronicle://server:35000")
      refute cs.skip_compatibility_check
      refute cs.skip_keep_alive
    end

    test "parses both flags" do
      cs =
        ConnectionString.parse(
          "chronicle://server:35000?skipCompatibilityCheck=true&skipKeepAlive=true"
        )

      assert cs.skip_compatibility_check
      assert cs.skip_keep_alive
    end
  end

  describe "parse/1 key casing and user information" do
    test "query keys are case-insensitive" do
      cs =
        ConnectionString.parse(
          "chronicle://server:35000?APIKEY=abc&skiptlsvalidation=false&DisableTls=true"
        )

      assert cs.api_key == "abc"
      refute cs.skip_tls_validation
      assert cs.disable_tls
    end

    test "unknown query keys are kept and round-trip" do
      cs = ConnectionString.parse("chronicle://server:35000?custom=value")
      assert ConnectionString.format(cs) == "chronicle://server:35000?custom=value"
    end

    test "raises when user information spilled an unencoded separator into the query" do
      assert_raise ArgumentError, ~r/percent-encoded/, fn ->
        ConnectionString.parse("chronicle://user:pa?ss@server:35000")
      end
    end

    test "raises for an at sign in an option that cannot hold one" do
      assert_raise ArgumentError, ~r/percent-encoded/, fn ->
        ConnectionString.parse("chronicle://server:35000?loadBalancer=a@b&disableTls=x@y")
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

  describe "insecure_remote?/1" do
    alias Cratis.Chronicle.Connections.ConnectionString

    test "the default against a remote host is insecure" do
      assert ConnectionString.insecure_remote?(
               ConnectionString.parse("chronicle://u:p@kernel.example.com:35000")
             )
    end

    test "local hosts, disabled TLS and explicit validation are not flagged" do
      refute ConnectionString.insecure_remote?(
               ConnectionString.parse("chronicle://u:p@localhost:35000")
             )

      refute ConnectionString.insecure_remote?(
               ConnectionString.parse("chronicle://u:p@127.0.0.1:35000")
             )

      refute ConnectionString.insecure_remote?(
               ConnectionString.parse("chronicle://u:p@kernel.example.com:35000?disableTls=true")
             )

      refute ConnectionString.insecure_remote?(
               ConnectionString.parse(
                 "chronicle://u:p@kernel.example.com:35000?skipTlsValidation=false"
               )
             )
    end
  end
end
