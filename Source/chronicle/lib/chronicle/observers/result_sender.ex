# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ResultSender do
  @moduledoc false

  # Sends an observer's result on its observation stream without taking the
  # handler down when the send fails.
  #
  # A send is a GenServer.call into the gRPC adapter's connection process with
  # the default 5 second timeout, and that process queues every request body
  # for the connection behind the one waiting on HTTP/2 flow control. A busy or
  # dead connection therefore makes the send exit, which used to crash the
  # handler process. The kernel already treats an unanswered delivery as failed
  # and redelivers it, so the handler only has to reopen its stream.

  require Logger

  @failed_event [:chronicle, :observer, :result, :send_failed]

  @typedoc "Sends a request on a stream. Replaceable in tests."
  @type send_fun :: (term(), term() -> term())

  @doc """
  Sends `result` on `stream`. Returns `:ok`, or `{:error, reason}` when the send
  raised or exited, after logging it and emitting
  `[:chronicle, :observer, :result, :send_failed]` telemetry with
  `%{observer: observer, reason: reason}` metadata.
  """
  @spec send_result(term(), term(), term(), send_fun()) :: :ok | {:error, term()}
  def send_result(stream, result, observer, send_fun \\ &GRPC.Stub.send_request/2) do
    send_fun.(stream, result)
    :ok
  rescue
    error -> failed(observer, error)
  catch
    :exit, reason -> failed(observer, reason)
  end

  defp failed(observer, reason) do
    Logger.warning(
      "Observer #{inspect(observer)} could not send its result, so it reopens its stream " <>
        "and the kernel redelivers the events: #{inspect(reason)}"
    )

    :telemetry.execute(@failed_event, %{count: 1}, %{observer: observer, reason: reason})
    {:error, reason}
  end
end
