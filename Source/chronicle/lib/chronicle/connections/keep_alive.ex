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

  alias Cratis.Chronicle.Contracts.Clients.ConnectionService
  alias Cratis.Chronicle.Contracts.Clients.ConnectionKeepAlive, as: KeepAliveMessage

  @typedoc "Answers a single keepalive. Replaceable in tests."
  @type answer_fun :: (GRPC.Channel.t(), String.t() -> :ok | {:error, term()})

  @doc """
  Consumes the Connect reply stream, answering every keepalive and reporting
  liveness back to `handler`.

  Sends `:keepalive_received` to `handler` for each keepalive, and exactly one
  `{:session_down, reason}` once the stream errors, ends, or an answer fails.
  """
  @spec run(pid(), Enumerable.t(), GRPC.Channel.t(), String.t(), answer_fun()) :: :ok
  def run(handler, reply_stream, channel, connection_id, answer_fun \\ &__MODULE__.answer/2) do
    reason =
      Enum.reduce_while(reply_stream, :stream_ended, fn
        {:ok, _keepalive}, _acc ->
          send(handler, :keepalive_received)

          case answer_fun.(channel, connection_id) do
            :ok -> {:cont, :stream_ended}
            {:error, reason} -> {:halt, {:keepalive_failed, reason}}
          end

        {:error, reason}, _acc ->
          {:halt, reason}
      end)

    send(handler, {:session_down, reason})
    :ok
  end

  @doc """
  Answers a single keepalive by calling the unary ConnectionKeepAlive RPC.
  """
  @spec answer(GRPC.Channel.t(), String.t()) :: :ok | {:error, term()}
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
