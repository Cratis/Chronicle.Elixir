# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.LoadBalancer.HttpProbe do
  @moduledoc """
  Default HTTP transport for `Chronicle.Connections.LoadBalancer`'s
  `:least_connections` strategy.

  Talks to a Chronicle kernel's `GET /connections/count` and
  `POST /connections/reserve` endpoints via `:httpc` (built into `:inets`, so
  no extra dependency is needed). TLS behavior mirrors the gRPC channel and
  the OAuth2 token fetch: skipped entirely when `disable_tls` is set, validated
  against the system trust store by default, and validation-skipped only when
  `skip_tls_validation` is explicitly set.

  The `/connections/count` response body is accepted either as a bare integer
  or as JSON with a `count` or `connections` key, since the exact response
  shape is a Chronicle kernel implementation detail this client doesn't
  otherwise depend on.
  """

  alias Chronicle.Connections.ConnectionString
  alias Chronicle.Connections.ConnectionString.ServerAddress

  @probe_timeout_ms 2_000

  @doc """
  Performs the `:count` or `:reserve` HTTP probe against `address`.
  """
  @spec request(:count | :reserve, ServerAddress.t(), ConnectionString.t()) ::
          {:ok, term()} | {:error, term()}
  def request(:count, address, connection_string) do
    with {:ok, body} <- get(address, connection_string, "/connections/count") do
      parse_count(body)
    end
  end

  def request(:reserve, address, connection_string) do
    post(address, connection_string, "/connections/reserve")
  end

  defp get(address, connection_string, path) do
    url = build_url(address, connection_string, path)

    case :httpc.request(:get, {url, []}, http_options(connection_string), []) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, to_string(body)}
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post(address, connection_string, path) do
    url = build_url(address, connection_string, path)
    request = {url, [], ~c"application/json", "{}"}

    case :httpc.request(:post, request, http_options(connection_string), []) do
      {:ok, {{_version, status, _reason}, _headers, body}} when status in 200..299 ->
        {:ok, to_string(body)}

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(%ServerAddress{host: host, port: port}, connection_string, path) do
    scheme = if connection_string.disable_tls, do: "http", else: "https"
    String.to_charlist("#{scheme}://#{host}:#{port}#{path}")
  end

  defp http_options(connection_string) do
    base = [connect_timeout: @probe_timeout_ms, timeout: @probe_timeout_ms]

    cond do
      connection_string.disable_tls ->
        base

      connection_string.skip_tls_validation ->
        Keyword.put(base, :ssl, verify: :verify_none)

      true ->
        Keyword.put(base, :ssl, verify: :verify_peer, cacerts: :public_key.cacerts_get())
    end
  end

  defp parse_count(body) do
    case Integer.parse(String.trim(body)) do
      {count, ""} ->
        {:ok, count}

      _not_a_bare_integer ->
        case Jason.decode(body) do
          {:ok, %{"count" => count}} when is_integer(count) -> {:ok, count}
          {:ok, %{"connections" => count}} when is_integer(count) -> {:ok, count}
          _other -> {:error, {:invalid_count_response, body}}
        end
    end
  end
end
