# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.StreamErrors do
  @moduledoc false

  # Classifies why a reactor or reducer observation stream ended, mirroring the
  # .NET client's KernelConnectionErrors:
  #
  #   * `:cancelled` - the client cancelled the stream itself.
  #   * `:connection_lost` - the kernel is stopping or unreachable (gRPC Unavailable).
  #   * `:session_lost` - the kernel no longer knows this client's connection id
  #     (`ClientIsNotConnected`), typically because it restarted. Retrying the same
  #     stream with the same connection id can never work; the whole client must
  #     reconnect with a new connection id.
  #   * `:failure` - anything else.

  # gRPC status codes.
  @cancelled 1
  @unavailable 14

  @session_lost_marker "ClientIsNotConnected"

  @type kind :: :cancelled | :connection_lost | :session_lost | :failure

  @doc "Classifies the reason an observation stream ended."
  @spec classify(term()) :: kind()
  def classify(%GRPC.RPCError{status: @cancelled}), do: :cancelled
  def classify(%GRPC.RPCError{status: @unavailable}), do: :connection_lost

  def classify(%GRPC.RPCError{message: message}) do
    if session_lost?(message), do: :session_lost, else: :failure
  end

  def classify({:error, reason}), do: classify(reason)
  def classify({:shutdown, reason}), do: classify(reason)
  def classify(_reason), do: :failure

  defp session_lost?(message) when is_binary(message),
    do: String.contains?(message, @session_lost_marker)

  defp session_lost?(_message), do: false
end
