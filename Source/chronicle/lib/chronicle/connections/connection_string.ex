# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ConnectionString do
  @moduledoc """
  Parses and formats Chronicle connection strings.

  Chronicle connection strings use the `chronicle://` or `chronicle+srv://` scheme:

      chronicle://localhost:35000
      chronicle://client-id:client-secret@server:35000
      chronicle://server:35000?apiKey=my-key&disableTls=true

  ## Authentication

  Two authentication modes are supported:

    * **Client credentials** — provide username and password in the URL userinfo:
      `chronicle://client-id:secret@host:35000`
    * **API key** — provide an `apiKey` query parameter:
      `chronicle://host:35000?apiKey=my-key`

  ## Query Parameters

    * `apiKey` — API key for authentication
    * `disableTls` — set to `"true"` to disable TLS (useful for local development)
    * `certificatePath` — path to a client certificate file
    * `certificatePassword` — password for the client certificate

  ## Examples

      iex> cs = Chronicle.Connections.ConnectionString.default()
      iex> cs.server_address.host
      "localhost"

      iex> cs = Chronicle.Connections.ConnectionString.parse("chronicle://localhost:35000?disableTls=true")
      iex> cs.disable_tls
      true
  """

  @default_port 35_000
  @development_client "chronicle-dev-client"
  @development_client_secret "chronicle-dev-secret"

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
            server_address: nil,
            username: nil,
            password: nil,
            api_key: nil,
            disable_tls: false,
            certificate_path: nil,
            certificate_password: nil,
            auth_port: nil,
            query_parameters: %{}

  @type t :: %__MODULE__{
          scheme: String.t(),
          server_address: ServerAddress.t() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          api_key: String.t() | nil,
          disable_tls: boolean(),
          certificate_path: String.t() | nil,
          certificate_password: String.t() | nil,
          auth_port: non_neg_integer() | nil,
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
    parse("chronicle://#{@development_client}:#{@development_client_secret}@localhost:#{@default_port}")
  end

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
    uri = URI.parse(connection_string)
    scheme = uri.scheme || raise ArgumentError, "Connection string must include a scheme"

    if scheme not in ["chronicle", "chronicle+srv"] do
      raise ArgumentError, "Unsupported Chronicle scheme '#{scheme}'"
    end

    host =
      case uri.host do
        h when is_binary(h) and h != "" -> h
        _ -> raise ArgumentError, "Connection string must include a host"
      end
    port = if uri.port in [nil, -1], do: @default_port, else: uri.port

    if port < 1 or port > 65_535 do
      raise ArgumentError, "Connection string port must be between 1 and 65535"
    end

    {username, password} = parse_user_info(uri.userinfo)
    query_parameters = parse_query(uri.query)

    auth_port =
      case Map.get(query_parameters, "authPort") do
        nil -> nil
        p -> String.to_integer(p)
      end

    %__MODULE__{
      scheme: scheme,
      server_address: %ServerAddress{host: host, port: port},
      username: username,
      password: password,
      api_key: Map.get(query_parameters, "apiKey"),
      disable_tls: String.downcase(Map.get(query_parameters, "disableTls", "false")) == "true",
      certificate_path: Map.get(query_parameters, "certificatePath"),
      certificate_password: Map.get(query_parameters, "certificatePassword"),
      auth_port: auth_port,
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

    %{connection_string | username: username, password: password, api_key: nil, query_parameters: updated_query_parameters}
  end

  @doc """
  Returns a new connection string with the given API key.

  Removes any existing client credentials.
  """
  @spec with_api_key(t(), String.t()) :: t()
  def with_api_key(%__MODULE__{} = connection_string, api_key) do
    query_parameters = Map.put(connection_string.query_parameters, "apiKey", api_key)

    %{connection_string | username: nil, password: nil, api_key: api_key, query_parameters: query_parameters}
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
        connection_string.server_address,
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

  defp build_authority(server_address, username, password) do
    credentials =
      cond do
        present?(username) and present?(password) ->
          "#{URI.encode_www_form(username)}:#{URI.encode_www_form(password)}@"

        present?(username) ->
          "#{URI.encode_www_form(username)}@"

        true ->
          ""
      end

    "#{credentials}#{server_address.host}:#{server_address.port}"
  end

  defp present?(value), do: is_binary(value) and value != ""
end

defimpl String.Chars, for: Chronicle.Connections.ConnectionString do
  def to_string(connection_string) do
    Chronicle.Connections.ConnectionString.format(connection_string)
  end
end
