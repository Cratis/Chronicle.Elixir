# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.KeepAlive do
  @moduledoc false

  # Drives the client half of Chronicle's keepalive ping-pong.
  #
  # The kernel pushes a ConnectionKeepAlive down the Connect server stream once
  # per second. For each one the client must call back the *separate* unary
  # ConnectionKeepAlive RPC, which bumps LastSeen on the kernel's
  # ConnectedClients grain. A client that only consumes the stream without ever
  # answering is evicted once LastSeen falls more than 5 seconds behind, and the
  # kernel then unsubscribes its observers — so reactors and reducers go silent
  # roughly a minute after startup while the Connect stream itself stays open
  # and every append keeps working. This mirrors the C# client's
  # ChronicleConnection.HandleConnection.

  require Logger

  alias Cratis.Chronicle.Contracts.Clients.ConnectionService
  alias Cratis.Chronicle.Contracts.Clients.ConnectionKeepAlive, as: KeepAliveMessage

  @typedoc "Answers a single keepalive. Replaceable in tests."
  @type answer_fun :: (%GRPC.Channel{}, String.t() -> :ok | {:error, term()})

  @doc """
  Consumes the Connect reply stream, answering every keepalive and reporting
  liveness back to `handler`.

  Sends `:keepalive_received` to `handler` for each keepalive, and exactly one
  `{:session_down, reason}` once the stream errors, ends, or an answer fails.
  """
  @spec run(pid(), Enumerable.t(), %GRPC.Channel{}, String.t(), answer_fun()) :: :ok
  def run(handler, reply_stream, channel, connection_id, answer_fun \\ &__MODULE__.answer/2) do
    {reason, _status} =
      Enum.reduce_while(reply_stream, {:stream_ended, :accepting}, fn
        {:ok, keepalive}, {_reason, status} ->
          send(handler, :keepalive_received)
          status = observe_status(status, keepalive)

          case answer_fun.(channel, connection_id) do
            :ok -> {:cont, {:stream_ended, status}}
            {:error, reason} -> {:halt, {{:keepalive_failed, reason}, status}}
          end

        {:error, reason}, {_reason, status} ->
          {:halt, {reason, status}}
      end)

    send(handler, {:session_down, reason})
    :ok
  end

  # The kernel says in each keepalive whether it is taking on work: `Accepting`, `Degraded` (busy)
  # or `Recovering`. A kernel that says nothing is accepting. The client logs when that changes and
  # otherwise carries on as before; its calls are retried by their own backoff.
  defp observe_status(previous, keepalive) do
    current = kernel_status(if is_map(keepalive), do: Map.get(keepalive, :Status))

    if current != previous do
      log_status_change(previous, current)
    end

    current
  end

  defp kernel_status(status) when status in [nil, :Accepting, 0], do: :accepting
  defp kernel_status(status) when status in [:Degraded, 1], do: :degraded
  defp kernel_status(status) when status in [:Recovering, 2], do: :recovering
  defp kernel_status(_unknown), do: :unknown

  defp log_status_change(_previous, :accepting),
    do: Logger.info("Chronicle is accepting calls normally again")

  defp log_status_change(_previous, :degraded),
    do:
      Logger.warning("Chronicle reports that it is busy; calls may be slow or be asked to retry")

  defp log_status_change(_previous, :recovering),
    do:
      Logger.warning(
        "Chronicle reports that it is recovering; calls may be slow or be asked to retry"
      )

  defp log_status_change(_previous, :unknown),
    do: Logger.warning("Chronicle reports a status this client does not know")

  @doc """
  Answers a single keepalive by calling the unary ConnectionKeepAlive RPC.
  """
  @spec answer(%GRPC.Channel{}, String.t()) :: :ok | {:error, term()}
  def answer(channel, connection_id) do
    case ConnectionService.Stub.connection_keep_alive(
           channel,
           struct(KeepAliveMessage, ConnectionId: connection_id)
         ) do
      {:ok, _empty} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end
end
