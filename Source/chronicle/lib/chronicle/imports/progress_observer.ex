# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ProgressObserver do
  @moduledoc false

  # Streams `ObserveImport` to a subscriber process as
  # `{:chronicle_import_progress, import_id, %ImportProgress{}}` messages, ending after the
  # first terminal state. A broken stream is reported as
  # `{:chronicle_import_progress_error, import_id, reason}`. The observer stops when the
  # subscriber exits.

  alias Chronicle.Imports.{Calls, Wire}
  alias Chronicle.WireResult

  @terminal [:completed, :failed, :abandoned]

  @spec start(Calls.target(), String.t(), pid()) :: {:ok, pid()}
  def start(target, import_id, subscriber) do
    {:ok, pid} = Task.start(fn -> run(target, import_id, subscriber) end)

    Task.start(fn ->
      ref = Process.monitor(subscriber)
      observer = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, _, _} -> Process.exit(pid, :shutdown)
        {:DOWN, ^observer, :process, _, _} -> :ok
      end
    end)

    {:ok, pid}
  end

  # An import that ended lets its observer deliver the final state before stopping it.
  @spec finish(pid() | nil, term()) :: :ok
  def finish(nil, _result), do: :ok

  def finish(pid, {:ok, %{state: state}}) when state in @terminal do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        stop(pid)
    end
  end

  def finish(pid, _result), do: stop(pid)

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) do
    Process.exit(pid, :shutdown)
    :ok
  end

  defp run(target, import_id, subscriber) do
    case Calls.observe(target, import_id) do
      {:ok, replies} ->
        Enum.reduce_while(replies, :ok, fn reply, :ok -> deliver(reply, import_id, subscriber) end)

      {:error, reason} ->
        send(subscriber, {:chronicle_import_progress_error, import_id, reason})
    end
  end

  defp deliver({:ok, envelope}, import_id, subscriber) do
    case WireResult.unwrap(envelope) do
      {:ok, nil} ->
        {:cont, :ok}

      {:ok, data} ->
        progress = Wire.progress(data, import_id)
        send(subscriber, {:chronicle_import_progress, import_id, progress})
        if progress.state in @terminal, do: {:halt, :ok}, else: {:cont, :ok}

      {:error, reason} ->
        send(subscriber, {:chronicle_import_progress_error, import_id, reason})
        {:halt, :ok}
    end
  end

  defp deliver({:error, reason}, import_id, subscriber) do
    send(subscriber, {:chronicle_import_progress_error, import_id, reason})
    {:halt, :ok}
  end
end
