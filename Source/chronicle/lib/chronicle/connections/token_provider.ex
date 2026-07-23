# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.TokenProvider do
  @moduledoc false

  # Owns the OAuth2 access token for a connection so it can be attached to
  # every RPC individually instead of being baked into the channel at dial
  # time. A channel-level token silently expires an hour in and takes the
  # whole session down with it; a per-call token is refreshed ahead of expiry
  # and never invalidates the channel.
  #
  # The token is fetched lazily on the first request and refreshed on demand
  # once it enters the refresh margin. RPCs flow continuously (the session
  # answers a keepalive every second), so on-demand refresh is proactive in
  # practice: the token is renewed within a second of entering the margin,
  # long before it expires. Fetch failures fall back to the cached token
  # while it is still valid, and retries are throttled so an auth outage
  # does not turn every RPC into a fetch attempt.

  use GenServer

  require Logger

  alias Chronicle.Connections.{Auth, ConnectionString}

  # Refresh once the token has less than this many milliseconds left.
  @refresh_margin 60_000
  # Minimum pause between failed fetch attempts.
  @failed_fetch_retry_delay 5_000
  # Assumed lifetime when the token response carries no expires_in.
  @default_expires_in 3_600

  @typedoc "Fetches a token. Replaceable in tests."
  @type fetch_fun ::
          (ConnectionString.t() -> {:ok, {String.t(), non_neg_integer() | nil}} | {:error, term()})

  @doc """
  Starts a token provider for the given connection string.

  ## Options

    * `:connection_string` — the `Chronicle.Connections.ConnectionString` whose
      credentials and authority to fetch tokens with (required).
    * `:fetch_fun` — test-only seam replacing the OAuth2 token fetch.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns the authorization headers for the next RPC.

  `%{"authorization" => "Bearer ..."}` with a token that is fresh (refreshed
  ahead of expiry when needed), or `%{}` when no token can be obtained — the
  RPC then fails with the server's auth rejection and the session machinery
  handles recovery.
  """
  @spec authorization_headers(GenServer.server()) :: %{optional(String.t()) => String.t()}
  def authorization_headers(provider) do
    GenServer.call(provider, :authorization_headers)
  end

  @impl true
  def init(opts) do
    state = %{
      connection_string: Keyword.fetch!(opts, :connection_string),
      fetch_fun: Keyword.get(opts, :fetch_fun, &default_fetch/1),
      token: nil,
      expires_at: nil,
      last_failed_fetch: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:authorization_headers, _from, state) do
    state = ensure_fresh_token(state)

    case state.token do
      nil -> {:reply, %{}, state}
      token -> {:reply, %{"authorization" => "Bearer #{token}"}, state}
    end
  end

  defp ensure_fresh_token(state) do
    cond do
      fresh?(state) -> state
      throttled?(state) -> state
      true -> fetch(state)
    end
  end

  defp fresh?(%{token: nil}), do: false
  defp fresh?(%{expires_at: expires_at}), do: expires_at - now_ms() > @refresh_margin

  defp throttled?(%{last_failed_fetch: nil}), do: false

  defp throttled?(%{last_failed_fetch: last_failed_fetch}) do
    now_ms() - last_failed_fetch < @failed_fetch_retry_delay
  end

  defp fetch(state) do
    case state.fetch_fun.(state.connection_string) do
      {:ok, {token, expires_in}} ->
        lifetime = (expires_in || @default_expires_in) * 1_000
        %{state | token: token, expires_at: now_ms() + lifetime, last_failed_fetch: nil}

      {:error, reason} ->
        Logger.warning("Failed to fetch OAuth2 token: #{inspect(reason)}")
        # Keep serving the cached token while it is still actually valid —
        # only the refresh margin has been crossed, not the expiry.
        state = %{state | last_failed_fetch: now_ms()}

        if state.token && state.expires_at > now_ms() do
          state
        else
          %{state | token: nil, expires_at: nil}
        end
    end
  end

  defp default_fetch(connection_string) do
    address = ConnectionString.server_address(connection_string)

    # Chronicle serves OAuth on the same port as the gRPC connection, on the
    # first configured host. Use explicit auth_port only when the caller
    # configured a distinct OAuth authority.
    port = connection_string.auth_port || address.port

    Auth.fetch_token_with_expiry(
      address.host,
      port,
      connection_string.username,
      connection_string.password,
      connection_string.disable_tls,
      connection_string.skip_tls_validation
    )
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
