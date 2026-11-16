# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ObservationStream do
  @moduledoc false

  # Opens and closes the bidirectional observation stream of a reactor or reducer handler,
  # shared by both handlers the way BatchRunner is.
  #
  # Opening a stream on a connection that has already closed does not raise: the adapter hands
  # back a stream that carries the error instead of a request, and sending the registration on it
  # would fail with a FunctionClauseError deep inside the adapter. The error is returned as the
  # reason the stream could not open.
  #
  # The adapter buffers the stream's responses in a process linked to the handler, which stops
  # only once its responses are read to the end. A handler tears its stream down without reading
  # it to the end - on every reconnect, on every lifecycle change - and lives as long as the
  # client, so the stream's response processes are stopped when the stream is given up
  # (see Chronicle.Connections.ResponseProcesses).

  alias Chronicle.Connections.ResponseProcesses

  @doc """
  Opens an observation stream with `observe` on `channel` and sends `registration` on it.

  Returns `{:error, reason}` - having stopped what the attempt started - when the stream cannot
  be opened or the registration cannot be sent.
  """
  @spec open(GRPC.Channel.t(), (GRPC.Channel.t() -> GRPC.Client.Stream.t()), struct()) ::
          {:ok, GRPC.Client.Stream.t(), [pid()]} | {:error, term()}
  def open(channel, observe, registration) do
    snapshot = ResponseProcesses.snapshot()

    try do
      case observe.(channel) do
        %GRPC.Client.Stream{payload: %{response: {:error, reason}}} ->
          failed(snapshot, reason)

        stream ->
          stream = GRPC.Stub.send_request(stream, registration)
          {:ok, stream, ResponseProcesses.started_since(snapshot)}
      end
    rescue
      error -> failed(snapshot, error)
    catch
      :exit, reason -> failed(snapshot, reason)
    end
  end

  @doc """
  Closes an observation stream the handler no longer reads: ends the request side so the kernel
  stops observing for it, then stops its response processes.

  Call it after stopping the process that reads the stream; a reader still waiting on a stopped
  response process would exit.
  """
  @spec close(GRPC.Client.Stream.t() | nil, [pid()]) :: :ok
  def close(nil, response_processes), do: ResponseProcesses.stop(response_processes)

  def close(stream, response_processes) do
    end_stream(stream)
    ResponseProcesses.stop(response_processes)
  end

  defp end_stream(stream) do
    GRPC.Stub.end_stream(stream)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp failed(snapshot, reason) do
    snapshot |> ResponseProcesses.started_since() |> ResponseProcesses.stop()
    {:error, reason}
  end
end
