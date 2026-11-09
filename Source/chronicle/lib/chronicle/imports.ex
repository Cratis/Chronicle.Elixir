# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports do
  @moduledoc """
  Imports large volumes of events into an event sequence.

  An import stages and validates every event before committing any, then commits them in
  order without locking the sequence, so ordinary appends keep working while it runs.
  Every reactor, reducer and projection sees each imported event once, as it would any
  appended event. Imported events keep their occurred time, correlation id, causation,
  caused-by identity, subject, tags and generation; each gets a new sequence number.

  ## Importing from any Enumerable

  `import/2` takes any `Enumerable` of `Chronicle.EventSequences.EventForEventSourceId`,
  a lazy `Stream` included. The source is read as the import uploads, so a 300 000-event
  import never holds 300 000 events in memory:

      {:ok, result} =
        "orders.jsonl"
        |> File.stream!()
        |> Stream.map(&MyApp.Legacy.to_event/1)
        |> Chronicle.Imports.import(progress: self())

      result.events_committed

  Events are cut into chunks within the limits the kernel reports, and at most four
  chunks are on the wire at once. A chunk whose connection fails is sent again; the
  kernel stages a chunk once, so resending never duplicates it.

  `import_async/2` runs the same import under a `Task`:

      task = Chronicle.Imports.import_async(events)
      {:ok, result} = Task.await(task, :infinity)

  ## An explicit session

  For producers that are not one stream, open the import yourself:

      {:ok, session} = Chronicle.Imports.begin()
      {:ok, session} = Chronicle.Imports.add(session, first_batch)
      {:ok, session} = Chronicle.Imports.add(session, second_batch)
      {:ok, result} = Chronicle.Imports.complete(session)

  `abandon/1` discards everything staged. An import that was not completed stays open on
  the kernel, so a process that crashed mid-way can `reattach/2` by its import id and
  continue after the last acknowledged event (`session.events_acknowledged`).
  `import/2` does that for you with `resume: import_id`, skipping the events the kernel
  already holds.

  ## Progress

  Pass `progress: pid` to `import/2`, or call `observe/2`, and the process receives

      {:chronicle_import_progress, import_id, %Chronicle.Imports.ImportProgress{}}

  until the import completes, fails or is abandoned. A broken progress stream is
  reported as `{:chronicle_import_progress_error, import_id, reason}`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — the event sequence to import into (default: `"event-log"`)
    * `:on_invalid` — `:reject` (default) commits nothing when any event is invalid;
      `:skip` commits the valid events and reports the rest
    * `:import_id` — the id to give a new import; beginning with an existing id returns it
    * `:wait_for_commit` — `complete/1` waits until the import is committed (default `true`)
    * `:max_chunks_in_flight` — chunks on the wire at once (default `4`)
    * `:max_events_per_chunk` — caps chunk size below the kernel's own limit
    * `:max_chunk_attempts` — attempts per chunk on connection failure (default `5`)
    * `:retry_delay` — `fn attempt -> milliseconds end` between attempts
    * `:poll_interval` — milliseconds between reads while waiting for the commit (default `500`)
    * `:timeout` — gRPC deadline per call in milliseconds (default `60_000`)

  Imports are never buffered by a `Chronicle.Transactions.UnitOfWork`. A kernel without
  the import service answers `{:error, :imports_not_supported}`.
  """

  alias Chronicle.Imports.{Calls, ImportResult, ProgressObserver, Session, Wire}

  @event_log_id "event-log"
  @terminal [:completed, :failed, :abandoned]

  @doc """
  Imports `events` and returns the result once the import is committed.

  Accepts every option in the module documentation, plus `:progress` (a pid receiving
  progress messages) and `:resume` (an import id to reattach to and continue).
  """
  @spec import(Enumerable.t(), keyword()) :: {:ok, ImportResult.t()} | {:error, term()}
  def import(events, opts \\ []) do
    with {:ok, session} <- open(opts) do
      observer = start_progress(session, Keyword.get(opts, :progress))

      remaining = Stream.drop(events, session.events_acknowledged)

      result =
        try do
          with {:ok, session} <- add(session, remaining), do: complete(session)
        rescue
          exception ->
            ProgressObserver.stop(observer)
            reraise exception, __STACKTRACE__
        end

      ProgressObserver.finish(observer, result)
      result
    end
  end

  @doc """
  Runs `import/2` under a `Task` linked to the caller. Await it with `Task.await/2`.
  """
  @spec import_async(Enumerable.t(), keyword()) :: Task.t()
  def import_async(events, opts \\ []), do: Task.async(fn -> __MODULE__.import(events, opts) end)

  @doc """
  Begins an import and returns its session.
  """
  @spec begin(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def begin(opts \\ []) do
    sequence = Keyword.get(opts, :event_sequence_id, @event_log_id)
    on_invalid = Keyword.get(opts, :on_invalid, :reject)

    with {:ok, target} <- Calls.resolve(opts),
         {:ok, response} <- Calls.begin(target, sequence, on_invalid, opts[:import_id]) do
      limits = %{
        max_chunk_events: Map.get(response, :MaxChunkEvents),
        max_chunk_bytes: Map.get(response, :MaxChunkBytes),
        acknowledged_chunks: 0,
        acknowledged_events: 0
      }

      import_id = Wire.guid_to_string(Map.get(response, :ImportId)) || opts[:import_id]
      {:ok, Session.new(import_id, sequence, target, limits, opts)}
    end
  end

  @doc """
  Reattaches to an import that was begun earlier, continuing after the chunks the kernel
  already acknowledged. The import's own `:on_invalid` applies.
  """
  @spec reattach(String.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def reattach(import_id, opts \\ []) when is_binary(import_id) do
    sequence = Keyword.get(opts, :event_sequence_id, @event_log_id)

    with {:ok, target} <- Calls.resolve(opts),
         {:ok, progress} <- Calls.get(target, import_id),
         :ok <- check_reattach(import_id, sequence, progress) do
      limits = %{
        max_chunk_events: Map.get(progress, :MaxChunkEvents),
        max_chunk_bytes: Map.get(progress, :MaxChunkBytes),
        acknowledged_chunks: Map.get(progress, :AcknowledgedChunks, 0),
        acknowledged_events: Map.get(progress, :AcknowledgedEvents, 0)
      }

      opts =
        Keyword.put(opts, :on_invalid, Wire.on_invalid_from_wire(Map.get(progress, :OnInvalid)))

      {:ok, Session.new(import_id, sequence, target, limits, opts)}
    end
  end

  @doc """
  Adds events to an open import. Returns the session to use next, once every chunk it
  sent is acknowledged; events that do not fill a chunk stay buffered until the next
  `add/2` or `complete/1`.
  """
  @spec add(Session.t(), Enumerable.t()) :: {:ok, Session.t()} | {:error, term()}
  defdelegate add(session, events), to: Session

  @doc """
  Completes an import: sends what is buffered, closes staging and, unless the session was
  begun with `wait_for_commit: false`, waits until the import is committed or fails.

  An import the kernel rejects is still `{:ok, result}`, with `result.state` `:failed`
  and the reasons in `result.rejections` and `result.failure_reason`.
  """
  @spec complete(Session.t()) :: {:ok, ImportResult.t()} | {:error, term()}
  def complete(%Session{} = session) do
    with {:ok, session} <- Session.flush(session),
         {:ok, status} <-
           Calls.complete(
             session.target,
             session.import_id,
             session.chunks_sent,
             session.events_sent
           ) do
      case Wire.blank_to_nil(status && Map.get(status, :Error)) do
        nil when session.wait_for_commit -> wait_for_commit(session)
        error -> read(session, status, error)
      end
    end
  end

  @doc """
  Abandons an import, discarding everything staged. Nothing is committed.
  """
  @spec abandon(Session.t()) :: {:ok, ImportResult.t()} | {:error, term()}
  def abandon(%Session{} = session) do
    with {:ok, status} <- Calls.abandon(session.target, session.import_id) do
      read(session, status, Wire.blank_to_nil(status && Map.get(status, :Error)))
    end
  end

  @doc """
  Reads an import's current state.
  """
  @spec get(String.t(), keyword()) :: {:ok, ImportResult.t()} | {:error, term()}
  def get(import_id, opts \\ []) when is_binary(import_id) do
    with {:ok, target} <- Calls.resolve(opts) do
      case Calls.get(target, import_id) do
        {:ok, nil} -> {:error, {:import_not_found, import_id}}
        {:ok, progress} -> {:ok, Wire.result(progress, import_id)}
        error -> error
      end
    end
  end

  @doc """
  Sends an import's progress to a process (`:to`, default the caller) until it completes,
  fails or is abandoned. Returns the observing process; stop it early with `unobserve/1`.
  """
  @spec observe(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def observe(import_id, opts \\ []) when is_binary(import_id) do
    with {:ok, target} <- Calls.resolve(opts) do
      ProgressObserver.start(target, import_id, Keyword.get(opts, :to, self()))
    end
  end

  @doc "Stops an observer started by `observe/2`."
  @spec unobserve(pid()) :: :ok
  def unobserve(pid) when is_pid(pid), do: ProgressObserver.stop(pid)

  defp open(opts) do
    case Keyword.get(opts, :resume) do
      nil -> begin(opts)
      import_id -> reattach(import_id, opts)
    end
  end

  defp start_progress(_session, nil), do: nil

  defp start_progress(session, pid) when is_pid(pid) do
    {:ok, observer} = ProgressObserver.start(session.target, session.import_id, pid)
    observer
  end

  defp check_reattach(import_id, _sequence, nil), do: {:error, {:import_not_found, import_id}}

  defp check_reattach(import_id, sequence, progress) do
    case Map.get(progress, :EventSequenceId) do
      ^sequence -> :ok
      other -> {:error, {:import_targets_other_event_sequence, import_id, other}}
    end
  end

  defp wait_for_commit(session) do
    case Calls.get(session.target, session.import_id) do
      {:ok, nil} ->
        {:error, {:import_not_found, session.import_id}}

      {:ok, progress} ->
        result = Wire.result(progress, session.import_id)

        if result.state in @terminal do
          {:ok, result}
        else
          Process.sleep(session.poll_interval)
          wait_for_commit(session)
        end

      error ->
        error
    end
  end

  defp read(session, status, error) do
    case Calls.get(session.target, session.import_id) do
      {:ok, progress} when not is_nil(progress) ->
        {:ok, Wire.result(progress, session.import_id)}

      _ ->
        {:ok,
         %ImportResult{
           import_id: session.import_id,
           state: Wire.state(Map.get(status || %{}, :State, 0)),
           failure_reason: error
         }}
    end
  end
end
