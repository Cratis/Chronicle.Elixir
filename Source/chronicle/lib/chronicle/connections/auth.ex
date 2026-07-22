# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Auth do
  @moduledoc false

  # Fetches OAuth2 Bearer tokens using the client credentials grant via HTTP/2.

  require Logger

  @doc """
  Fetches an OAuth2 access token using the client credentials grant.

  POSTs to `http(s)://host:port/connect/token` with
  `grant_type=client_credentials`, `client_id`, and `client_secret`.

  `skip_tls_validation` mirrors the same option on the gRPC channel
  (`Chronicle.Connections.Connection`): when `true` (the default), the TLS
  certificate chain is not validated; set it to `false` to validate against
  the system trust store instead. Ignored when `disable_tls` is `true`.

  Returns `{:ok, token}` or `{:error, reason}`.
  """
  @spec fetch_token(
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          boolean(),
          boolean()
        ) :: {:ok, String.t()} | {:error, term()}
  def fetch_token(host, port, client_id, client_secret, disable_tls, skip_tls_validation \\ true) do
    scheme = if disable_tls, do: :http, else: :https

    body =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"content-length", Integer.to_string(byte_size(body))},
      {"accept", "application/json"}
    ]

    mint_opts = mint_transport_opts(disable_tls, skip_tls_validation)

    with {:ok, conn} <- Mint.HTTP.connect(scheme, host, port, mint_opts),
         {:ok, conn, _ref} <- Mint.HTTP.request(conn, "POST", "/connect/token", headers, body),
         {:ok, {status, resp_body}} <- receive_response(conn) do
      Mint.HTTP.close(conn)

      case status do
        200 ->
          case Jason.decode(resp_body) do
            {:ok, %{"access_token" => token}} -> {:ok, token}
            {:ok, resp} -> {:error, {:missing_access_token, resp}}
            {:error, reason} -> {:error, {:json_decode, reason}}
          end

        other ->
          {:error, {:http_error, other, resp_body}}
      end
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  defp mint_transport_opts(true, _skip_tls_validation), do: []
  defp mint_transport_opts(false, true), do: [transport_opts: [verify: :verify_none]]

  defp mint_transport_opts(false, false),
    do: [transport_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]]

  defp receive_response(conn, status \\ nil, body \\ "") do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {new_status, new_body, done?} =
              Enum.reduce(responses, {status, body, false}, fn
                {:status, _ref, s}, {_, b, d} -> {s, b, d}
                {:data, _ref, d}, {s, b, _} -> {s, b <> d, false}
                {:done, _ref}, {s, b, _} -> {s, b, true}
                _other, acc -> acc
              end)

            if done? do
              {:ok, {new_status, new_body}}
            else
              receive_response(conn, new_status, new_body)
            end

          {:error, _conn, reason, _} ->
            {:error, {:stream_error, reason}}

          :unknown ->
            receive_response(conn, status, body)
        end
    after
      10_000 ->
        {:error, :timeout}
    end
  end
end
