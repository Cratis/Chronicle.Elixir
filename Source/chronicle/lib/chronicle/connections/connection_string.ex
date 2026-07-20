# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionString do
  @moduledoc """
  Parses and formats Chronicle connection strings.

  Chronicle connection strings use the `chronicle://` or `chronicle+srv://` scheme:

      chronicle://localhost:35000
      chronicle://client-id:client-secret@server:35000
      chronicle://server:35000?apiKey=my-key

  ## Multiple hosts

  A `chronicle://` connection string may list more than one host, comma-separated.
  Every configured host is a candidate the load balancer can pick between (see
  `Chronicle.Connections.Connection`):

      chronicle://host1:35000,host2:35000,host3:35000
      chronicle://client-id:secret@host1:35000,host2:35000

  IPv6 literals must use bracket notation, exactly like standard URLs:

      chronicle://[::1]:35000
      chronicle://[2001:db8::1]:35000,[2001:db8::2]:35000

  A host without an explicit port uses the default (`35000`).

  ## DNS SRV discovery

  `chronicle+srv://` resolves its single host to a set of Chronicle server
  addresses via a DNS SRV lookup (query name `_chronicle._tcp.<host>`) instead of
  listing hosts explicitly. It is re-resolved on every connect/reconnect attempt,
  so membership changes are picked up automatically:

      chronicle+srv://my-chronicle-service

  A `chronicle+srv://` connection string supports only a single host; use
  `srvNameServer` to query a specific DNS server instead of the system resolver.

  ## Authentication

  Two authentication modes are supported:

    * **Client credentials** — provide username and password in the URL userinfo:
      `chronicle://client-id:secret@host:35000`
    * **API key** — provide an `apiKey` query parameter:
      `chronicle://host:35000?apiKey=my-key`

  ## Query Parameters

    * `apiKey` — API key for authentication
    * `disableTls` — set to `"true"` to disable TLS (only for connecting through
      something else that terminates TLS for you, such as a plaintext-terminating
      proxy; the Chronicle kernel requires TLS on its single port, including in
      development)
    * `skipTlsValidation` — set to `"false"` to require full TLS certificate
      chain validation against the system trust store. Distinct from
      `disableTls`: TLS stays on either way, this only controls whether the
      chain is validated. Defaults to `true` — a Chronicle kernel commonly
      serves an auto-generated self-signed certificate, so validation is
      skipped unless explicitly turned on.
    * `certificatePath` — path to a client certificate file
    * `certificatePassword` — password for the client certificate
    * `loadBalancer` — strategy used to pick among multiple hosts (or
      SRV-resolved addresses): `"least-connections"` (default), `"round-robin"`,
      or `"random"`. See `Chronicle.Connections.LoadBalancer`.
    * `srvNameServer` — for `chronicle+srv://`, a specific DNS server
      (`"host"` or `"host:port"`) to query instead of the system resolver.

  ## Examples

      iex> cs = Chronicle.Connections.ConnectionString.default()
      iex> Chronicle.Connections.ConnectionString.server_address(cs).host
      "localhost"

      iex> cs = Chronicle.Connections.ConnectionString.parse("chronicle://localhost:35000?disableTls=true")
      iex> cs.disable_tls
      true
  """

  @default_port 35_000
  @development_client "chronicle-dev-client"
  @development_client_secret "chronicle-dev-secret"

  @load_balancer_strategies %{
    "least-connections" => :least_connections,
    "round-robin" => :round_robin,
    "random" => :random
  }

  defmodule ServerAddress do
    @moduledoc """
    Represents a Chronicle server address with host and port.
    """

    defstruct host: nil, port: nil

    @type t :: %__MODULE__{
            host: String.t() | nil,
            port: non_neg_integer() | nil
          }
  end

  defstruct scheme: "chronicle",
            server_addresses: [],
            username: nil,
            password: nil,
            api_key: nil,
            disable_tls: false,
            skip_tls_validation: true,
            certificate_path: nil,
            certificate_password: nil,
            auth_port: nil,
            load_balancer: :least_connections,
            srv_name_server: nil,
            query_parameters: %{}

  @type load_balancer_strategy :: :least_connections | :round_robin | :random

  @type t :: %__MODULE__{
          scheme: String.t(),
          server_addresses: [ServerAddress.t()],
          username: String.t() | nil,
          password: String.t() | nil,
          api_key: String.t() | nil,
          disable_tls: boolean(),
          skip_tls_validation: boolean(),
          certificate_path: String.t() | nil,
          certificate_password: String.t() | nil,
          auth_port: non_neg_integer() | nil,
          load_balancer: load_balancer_strategy(),
          srv_name_server: String.t() | nil,
          query_parameters: %{optional(String.t()) => String.t()}
        }

  @doc """
  Returns the default local development connection string without authentication.

  Connects to `localhost:35000` with no TLS or credentials.
  """
  @spec default() :: t()
  def default do
    parse("chronicle://localhost:#{@default_port}")
  end

  @doc """
  Returns the Chronicle development connection string with default credentials.

  Uses the built-in development client ID and secret for a local Chronicle instance.
  """
  @spec development() :: t()
  def development do
    parse(
      "chronicle://#{@development_client}:#{@development_client_secret}@localhost:#{@default_port}"
    )
  end

  @doc """
  Returns the first configured server address.

  Provided as a convenience for callers that only need a single address — such
  as the OAuth2 token endpoint, which authenticates against the first
  configured host rather than the address the load balancer eventually picks
  for the gRPC channel itself. Multi-host and `chronicle+srv://` connection
  strings still resolve and select among every address for the channel; see
  `Chronicle.Connections.Connection` and `Chronicle.Connections.LoadBalancer`.
  """
  @spec server_address(t()) :: ServerAddress.t() | nil
  def server_address(%__MODULE__{server_addresses: [address | _]}), do: address
  def server_address(%__MODULE__{server_addresses: []}), do: nil

  @doc """
  Parses a Chronicle connection string into a `ConnectionString` struct.

  Raises `ArgumentError` if the connection string is malformed.

  ## Examples

      iex> cs = Chronicle.Connections.ConnectionString.parse("chronicle://server:35000?apiKey=abc")
      iex> cs.api_key
      "abc"
  """
  @spec parse(String.t()) :: t()
  def parse(connection_string) when is_binary(connection_string) do
    {scheme, remainder} = split_scheme(connection_string)
    validate_scheme!(scheme)

    {authority, query_string} = split_query(remainder)
    {user_info, hosts_part} = split_user_info(authority)
    {username, password} = parse_user_info(user_info)
    query_parameters = parse_query(query_string)

    server_addresses = parse_hosts(hosts_part)

    if scheme == "chronicle+srv" and length(server_addresses) > 1 do
      raise ArgumentError, "chronicle+srv connection strings support only a single host"
    end

    auth_port =
      case Map.get(query_parameters, "authPort") do
        nil -> nil
        p -> String.to_integer(p)
      end

    %__MODULE__{
      scheme: scheme,
      server_addresses: server_addresses,
      username: username,
      password: password,
      api_key: Map.get(query_parameters, "apiKey"),
      disable_tls: flag?(query_parameters, "disableTls", false),
      skip_tls_validation: flag?(query_parameters, "skipTlsValidation", true),
      certificate_path: Map.get(query_parameters, "certificatePath"),
      certificate_password: Map.get(query_parameters, "certificatePassword"),
      auth_port: auth_port,
      load_balancer: parse_load_balancer(query_parameters),
      srv_name_server: Map.get(query_parameters, "srvNameServer"),
      query_parameters: query_parameters
    }
  end

  @doc """
  Returns the configured authentication mode for the connection string.

  Returns `:client_credentials` if username and password are set,
  `:api_key` if an API key is set, or `:none` if no authentication is configured.

  Raises `ArgumentError` if both client credentials and API key are specified.

  ## Examples

      iex> cs = Chronicle.Connections.ConnectionString.parse("chronicle://user:pass@server:35000")
      iex> Chronicle.Connections.ConnectionString.authentication_mode(cs)
      :client_credentials
  """
  @spec authentication_mode(t()) :: :client_credentials | :api_key | :none
  def authentication_mode(%__MODULE__{} = connection_string) do
    has_credentials? =
      present?(connection_string.username) and
        present?(connection_string.password)

    has_api_key? = present?(connection_string.api_key)

    cond do
      has_credentials? and has_api_key? ->
        raise ArgumentError, "Cannot specify both client credentials and API key authentication"

      has_credentials? ->
        :client_credentials

      has_api_key? ->
        :api_key

      true ->
        :none
    end
  end

  @doc """
  Returns a new connection string with the given client credentials.

  Removes any existing API key.
  """
  @spec with_credentials(t(), String.t(), String.t()) :: t()
  def with_credentials(%__MODULE__{} = connection_string, username, password) do
    updated_query_parameters = Map.delete(connection_string.query_parameters, "apiKey")

    %{
      connection_string
      | username: username,
        password: password,
        api_key: nil,
        query_parameters: updated_query_parameters
    }
  end

  @doc """
  Returns a new connection string with the given API key.

  Removes any existing client credentials.
  """
  @spec with_api_key(t(), String.t()) :: t()
  def with_api_key(%__MODULE__{} = connection_string, api_key) do
    query_parameters = Map.put(connection_string.query_parameters, "apiKey", api_key)

    %{
      connection_string
      | username: nil,
        password: nil,
        api_key: api_key,
        query_parameters: query_parameters
    }
  end

  @doc """
  Converts the connection string struct back to its URI string representation.

  ## Examples

      iex> cs = Chronicle.Connections.ConnectionString.default()
      iex> Chronicle.Connections.ConnectionString.format(cs)
      "chronicle://localhost:35000"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = connection_string) do
    authority =
      build_authority(
        connection_string.server_addresses,
        connection_string.username,
        connection_string.password
      )

    query =
      connection_string.query_parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("&", fn {key, value} ->
        "#{URI.encode_www_form(key)}=#{URI.encode_www_form(value)}"
      end)

    if query == "" do
      "#{connection_string.scheme}://#{authority}"
    else
      "#{connection_string.scheme}://#{authority}?#{query}"
    end
  end

  # -- Parsing -------------------------------------------------------------
  #
  # `URI.parse/1` cannot represent comma-separated hosts, so the authority
  # (userinfo + host list) is hand-rolled here instead of relying on it.

  defp split_scheme(connection_string) do
    case String.split(connection_string, "://", parts: 2) do
      [scheme, rest] when scheme != "" -> {scheme, rest}
      _ -> raise ArgumentError, "Connection string must include a scheme"
    end
  end

  defp validate_scheme!(scheme) do
    if scheme not in ["chronicle", "chronicle+srv"] do
      raise ArgumentError, "Unsupported Chronicle scheme '#{scheme}'"
    end
  end

  defp split_query(remainder) do
    case String.split(remainder, "?", parts: 2) do
      [authority, query] -> {authority, query}
      [authority] -> {authority, nil}
    end
  end

  defp split_user_info(authority) do
    case String.split(authority, "@") do
      [hosts] ->
        {nil, hosts}

      parts ->
        # The host list can't legally contain "@", so any occurrence is the
        # userinfo separator — mirroring how URI.parse treats the *last* "@"
        # in the authority as the boundary.
        {parts |> Enum.slice(0..-2//1) |> Enum.join("@"), List.last(parts)}
    end
  end

  defp parse_user_info(nil), do: {nil, nil}

  defp parse_user_info(user_info) do
    case String.split(user_info, ":", parts: 2) do
      [username, password] ->
        {URI.decode_www_form(username), URI.decode_www_form(password)}

      [username] ->
        {URI.decode_www_form(username), nil}
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)

  defp parse_hosts(hosts_part) do
    hosts_part
    |> String.split(",")
    |> Enum.map(&parse_host_entry/1)
  end

  defp parse_host_entry(entry) do
    entry = String.trim(entry)
    {host, port} = split_host_and_port(entry)

    if host == nil or host == "" do
      raise ArgumentError, "Connection string must include a host"
    end

    port = port || @default_port

    if port < 1 or port > 65_535 do
      raise ArgumentError, "Connection string port must be between 1 and 65535"
    end

    %ServerAddress{host: host, port: port}
  end

  defp split_host_and_port("[" <> _ = entry) do
    case Regex.run(~r/^\[(?<host>[^\]]*)\](?::(?<port>[0-9]+))?$/, entry) do
      [_full, host, port] -> {host, parse_port!(port)}
      [_full, host] -> {host, nil}
      nil -> raise ArgumentError, "Invalid IPv6 host segment '#{entry}'"
    end
  end

  defp split_host_and_port(entry) do
    case String.split(entry, ":") do
      [host] ->
        {host, nil}

      [host, port] ->
        {host, parse_port!(port)}

      _more_than_one_colon ->
        # A bare IPv6 literal without a port — bracket notation is required to
        # pair an IPv6 host with a port, so the whole entry is just the host.
        {entry, nil}
    end
  end

  defp parse_port!(port_string) do
    case Integer.parse(port_string) do
      {port, ""} -> port
      _ -> raise ArgumentError, "Connection string port must be between 1 and 65535"
    end
  end

  defp flag?(query_parameters, key, default) do
    default_string = if default, do: "true", else: "false"
    String.downcase(Map.get(query_parameters, key, default_string)) == "true"
  end

  defp parse_load_balancer(query_parameters) do
    case Map.get(query_parameters, "loadBalancer") do
      nil ->
        :least_connections

      value ->
        Map.get(@load_balancer_strategies, value) ||
          raise ArgumentError,
                "Unsupported loadBalancer strategy '#{value}'. Supported values: " <>
                  Enum.map_join(@load_balancer_strategies, ", ", fn {name, _} -> name end)
    end
  end

  # -- Formatting ------------------------------------------------------------

  defp build_authority(server_addresses, username, password) do
    credentials =
      cond do
        present?(username) and present?(password) ->
          "#{URI.encode_www_form(username)}:#{URI.encode_www_form(password)}@"

        present?(username) ->
          "#{URI.encode_www_form(username)}@"

        true ->
          ""
      end

    hosts = Enum.map_join(server_addresses, ",", &format_host_port/1)

    "#{credentials}#{hosts}"
  end

  defp format_host_port(%ServerAddress{host: host, port: port}) do
    if ipv6_literal?(host) do
      "[#{host}]:#{port}"
    else
      "#{host}:#{port}"
    end
  end

  defp ipv6_literal?(host), do: String.contains?(host, ":")

  defp present?(value), do: is_binary(value) and value != ""
end

defimpl String.Chars, for: Chronicle.Connections.ConnectionString do
  def to_string(connection_string) do
    Chronicle.Connections.ConnectionString.format(connection_string)
  end
end
