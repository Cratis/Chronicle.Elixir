# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Observers.Multiplexed.ObserverStream do
  @moduledoc false

  # One reactor's or reducer's share of the multiplexed observation call. It stands where the
  # per-observer `GRPC.Client.Stream` stands for a handler: results go out with `send_request/2`,
  # deliveries come in through `recv/1`, and `Cratis.Chronicle.Observers.ObservationStream` closes it.

  alias Cratis.Chronicle.Observers.Multiplexed.Channel

  @enforce_keys [:server, :id, :kind]
  defstruct [:server, :id, :kind]

  @type t :: %__MODULE__{server: pid(), id: pos_integer(), kind: :reactor | :reducer}

  @doc "Sends an observer message (a result) on the stream."
  @spec send_request(t(), struct()) :: :ok
  def send_request(%__MODULE__{} = stream, message) do
    case Channel.send_message(stream, message) do
      :ok -> :ok
      {:error, reason} -> exit({:multiplexed_stream_closed, reason})
    end
  end

  @doc """
  The deliveries of the stream as an enumerable of `{:ok, delivery}` and, when the stream failed,
  a final `{:error, reason}`. It ends when the kernel completes the stream or the call ends.
  """
  @spec recv(t()) :: {:ok, Enumerable.t()}
  def recv(%__MODULE__{} = stream) do
    {:ok,
     Stream.resource(
       fn -> :open end,
       fn
         :halt ->
           {:halt, :halt}

         :open ->
           case Channel.next(stream) do
             {:message, message} -> {[{:ok, message}], :open}
             :done -> {:halt, :halt}
             {:error, reason} -> {[{:error, reason}], :halt}
           end
       end,
       fn _ -> :ok end
     )}
  end
end
