# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Connections.ResponseProcesses do
  @moduledoc false

  # The Mint adapter buffers the responses of every call in a process it starts and links to the
  # caller. That process stops only once its responses have been read to the end, so a call nobody
  # reads to the end leaves it behind for as long as the caller lives: a call that failed on a
  # closed connection, an observation stream torn down for a reconnect, a session stream abandoned
  # after a missed keepalive. The callers that hit those paths - observer handlers, the session,
  # anything polling the kernel - live as long as the client, so each abandoned call is a process
  # the node never gets back. Record the processes a call starts and stop them when it is given up.

  @response_process GRPC.Client.Adapters.Mint.StreamResponseProcess

  @typedoc "The calling process's links before a call."
  @opaque snapshot :: MapSet.t()

  @doc "Takes the links of the calling process, to compare against after a call."
  @spec snapshot() :: snapshot()
  def snapshot do
    {:links, links} = Process.info(self(), :links)
    MapSet.new(links)
  end

  @doc "The response processes the calling process was linked to since `snapshot`."
  @spec started_since(snapshot()) :: [pid()]
  def started_since(snapshot) do
    snapshot()
    |> MapSet.difference(snapshot)
    |> Enum.filter(&response_process?/1)
  end

  @doc """
  Stops response processes the calling process no longer reads from.

  Unlinks before stopping, so the caller is not taken down with them.
  """
  @spec stop([pid()]) :: :ok
  def stop(pids) do
    Enum.each(pids, fn pid ->
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end)
  end

  defp response_process?(pid) when is_pid(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        match?({@response_process, _, _}, Keyword.get(dictionary, :"$initial_call"))

      nil ->
        false
    end
  end

  defp response_process?(_port), do: false
end
