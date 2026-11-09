# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.Session do
  @moduledoc """
  An open import, as returned by `Chronicle.Imports.begin/1` and
  `Chronicle.Imports.reattach/2`.

  A session is a value: `Chronicle.Imports.add/2` returns the session to use next. It holds
  where the import has got to (`chunks_sent`, `events_sent`) and the events read but not
  yet sent, which stay buffered until they fill a chunk or the import is completed.

  `events_acknowledged` is how many events the kernel held when the session began or was
  reattached; a resumed producer skips that many events of its source.
  """

  alias Chronicle.EventSequences.{DefinitionRouting, EventForEventSourceId}
  alias Chronicle.Imports.{Calls, Wire}

  @enforce_keys [:import_id, :event_sequence_id, :target]
  defstruct [
    :import_id,
    :event_sequence_id,
    :target,
    on_invalid: :reject,
    max_chunk_events: 1_000,
    max_chunk_bytes: 4_194_304,
    max_chunks_in_flight: 4,
    retry: %{max_attempts: 5, delay: nil},
    wait_for_commit: true,
    poll_interval: 500,
    event_sources: [],
    chunks_sent: 0,
    events_sent: 0,
    events_acknowledged: 0,
    buffer: [],
    buffer_count: 0,
    buffer_bytes: 0
  ]

  @type t :: %__MODULE__{
          import_id: String.t(),
          event_sequence_id: String.t(),
          on_invalid: :reject | :skip,
          chunks_sent: non_neg_integer(),
          events_sent: non_neg_integer(),
          events_acknowledged: non_neg_integer()
        }

  @doc false
  @spec new(String.t(), String.t(), Calls.target(), map(), keyword()) :: t()
  def new(import_id, event_sequence_id, target, limits, opts) do
    server_events = positive_or(limits.max_chunk_events, nil)

    max_events =
      [server_events, Keyword.get(opts, :max_events_per_chunk)]
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> 1_000 end)

    %__MODULE__{
      import_id: import_id,
      event_sequence_id: event_sequence_id,
      target: target,
      on_invalid: Keyword.get(opts, :on_invalid, :reject),
      max_chunk_events: max(1, max_events),
      max_chunk_bytes: positive_or(limits.max_chunk_bytes, :infinity),
      max_chunks_in_flight: max(1, Keyword.get(opts, :max_chunks_in_flight, 4)),
      retry: %{
        max_attempts: max(1, Keyword.get(opts, :max_chunk_attempts, 5)),
        delay: Keyword.get(opts, :retry_delay, &default_retry_delay/1)
      },
      wait_for_commit: Keyword.get(opts, :wait_for_commit, true),
      poll_interval: Keyword.get(opts, :poll_interval, 500),
      event_sources: Map.get(target.config, :event_sources, []),
      chunks_sent: limits.acknowledged_chunks,
      events_sent: limits.acknowledged_events,
      events_acknowledged: limits.acknowledged_events
    }
  end

  @doc false
  # Reads `events` one at a time, cutting them into chunks and keeping at most
  # `max_chunks_in_flight` chunks on the wire. Returns once every chunk sent is acknowledged.
  @spec add(t(), Enumerable.t()) :: {:ok, t()} | {:error, term()}
  def add(%__MODULE__{} = session, events) do
    result =
      Enum.reduce_while(events, {session, []}, fn entry, {session, in_flight} ->
        case buffer(session, in_flight, entry) do
          {:ok, session, in_flight} -> {:cont, {session, in_flight}}
          {:error, reason, in_flight} -> {:halt, {:error, reason, in_flight}}
        end
      end)

    case result do
      {:error, reason, in_flight} ->
        settle(in_flight)
        {:error, reason}

      {session, in_flight} ->
        with :ok <- settle(in_flight), do: {:ok, session}
    end
  end

  @doc false
  # Sends what is still buffered and waits for it.
  @spec flush(t()) :: {:ok, t()} | {:error, term()}
  def flush(%__MODULE__{buffer_count: 0} = session), do: {:ok, session}

  def flush(%__MODULE__{} = session) do
    {session, in_flight} = send_buffer(session, [])
    with :ok <- settle(in_flight), do: {:ok, session}
  end

  defp buffer(session, in_flight, entry) do
    with {:ok, entry} <- route(session, entry),
         {:ok, event} <- Wire.to_import_event(entry) do
      bytes = Wire.size_of(event)

      {session, in_flight} =
        if full?(session, bytes), do: send_buffer(session, in_flight), else: {session, in_flight}

      session = %{
        session
        | buffer: [event | session.buffer],
          buffer_count: session.buffer_count + 1,
          buffer_bytes: session.buffer_bytes + bytes
      }

      # A chunk holding as many events as allowed goes out without waiting for the next event.
      {session, in_flight} =
        if session.buffer_count >= session.max_chunk_events,
          do: send_buffer(session, in_flight),
          else: {session, in_flight}

      {:ok, session, in_flight}
    else
      {:error, reason} -> {:error, reason, in_flight}
    end
  catch
    {:chunk_failed, reason, in_flight} -> {:error, reason, in_flight}
  end

  defp route(_session, %EventForEventSourceId{event_source: nil, event_stream: nil} = entry),
    do: {:ok, entry}

  defp route(session, %EventForEventSourceId{} = entry) do
    with {:ok, [entry]} <- DefinitionRouting.resolve([entry], session.event_sources),
         do: {:ok, entry}
  end

  defp route(_session, other), do: {:error, {:not_an_event_for_event_source_id, other}}

  defp full?(%{buffer_count: 0}, _bytes), do: false

  defp full?(session, bytes) do
    session.buffer_count >= session.max_chunk_events or
      (session.max_chunk_bytes != :infinity and
         session.buffer_bytes + bytes > session.max_chunk_bytes)
  end

  # Hands the buffer to a task once a slot is free. A failed chunk stops the import.
  defp send_buffer(session, in_flight) do
    in_flight =
      if length(in_flight) >= session.max_chunks_in_flight do
        case await_one(in_flight) do
          {:ok, rest} -> rest
          {:error, reason, rest} -> throw({:chunk_failed, reason, rest})
        end
      else
        in_flight
      end

    %{target: target, import_id: import_id, retry: retry} = session

    {index, first, events} =
      {session.chunks_sent, session.events_sent, Enum.reverse(session.buffer)}

    task =
      Task.async(fn ->
        safely(fn -> Calls.add_chunk(target, import_id, index, first, events, retry) end)
      end)

    session = %{
      session
      | chunks_sent: index + 1,
        events_sent: first + session.buffer_count,
        buffer: [],
        buffer_count: 0,
        buffer_bytes: 0
    }

    {session, [task | in_flight]}
  end

  defp safely(fun) do
    fun.()
  rescue
    exception -> {:error, {:import_chunk_failed, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:import_chunk_failed, {kind, reason}}}
  end

  defp await_one(tasks) do
    refs = Map.new(tasks, &{&1.ref, &1})

    receive do
      {ref, result} when is_map_key(refs, ref) ->
        Process.demonitor(ref, [:flush])
        rest = Enum.reject(tasks, &(&1.ref == ref))

        case result do
          {:ok, _} -> {:ok, rest}
          {:error, reason} -> {:error, reason, rest}
        end

      {:DOWN, ref, :process, _pid, reason} when is_map_key(refs, ref) ->
        {:error, {:import_chunk_failed, reason}, Enum.reject(tasks, &(&1.ref == ref))}
    end
  end

  # Waits for every chunk in flight; the first failure is the result.
  defp settle([]), do: :ok

  defp settle(in_flight) do
    case await_one(in_flight) do
      {:ok, rest} ->
        settle(rest)

      {:error, reason, rest} ->
        settle(rest)
        {:error, reason}
    end
  end

  defp positive_or(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or(_value, default), do: default

  defp default_retry_delay(attempt), do: min(5_000, 200 * attempt * attempt)
end
