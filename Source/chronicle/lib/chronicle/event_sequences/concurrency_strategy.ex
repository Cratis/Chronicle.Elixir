# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ConcurrencyStrategy do
  @moduledoc false

  # Applies the client's configured default concurrency strategy (the `:concurrency` option on
  # `Chronicle.Client`) to events that got neither an explicit concurrency scope nor one derived
  # from an event source definition's declared dimensions (`Chronicle.EventSequences.DefinitionRouting`).
  # Mirrors the .NET client's `OptimisticConcurrencyStrategy`: read the tail narrowed exactly the
  # way the append itself is routed, and expect nothing to have been appended since.

  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Events.ConcurrencyScope

  @unavailable_sequence_number 18_446_744_073_709_551_615

  @doc """
  Fills the concurrency scope of every event in `events` that still has none, according to
  `config`'s `:concurrency` option (`default: :none | :optimistic`, `check_first_append: boolean`).
  `tail_fun` is called as `tail_fun.(event_source_id, narrowing_opts)` and returns the raw
  (un-normalized) tail sequence number.

  `:guarded_event_sources` (default `[]`) lists event source ids that already carry a guard in
  this unit of work - an enrolled decision read. They get no default scope: the decision read
  is their guard, and the wire carries one scope per event source id.
  """
  @spec apply_default([EventForEventSourceId.t()], map(), function(), keyword()) ::
          {:ok, [EventForEventSourceId.t()]} | {:error, term()}
  def apply_default(events, config, tail_fun, opts \\ []) do
    case strategy(config) do
      :none ->
        {:ok, events}

      {:optimistic, check_first_append?} ->
        guarded = Keyword.get(opts, :guarded_event_sources, [])

        apply_optimistic(events, check_first_append?, tail_fun, guarded)
    end
  end

  defp strategy(config) do
    opts = Map.get(config, :concurrency, [])

    case Keyword.get(opts, :default, :none) do
      :optimistic -> {:optimistic, Keyword.get(opts, :check_first_append, false)}
      _ -> :none
    end
  end

  defp apply_optimistic(events, check_first_append?, tail_fun, guarded) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case derive_unless_guarded(event, check_first_append?, tail_fun, guarded) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, result} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp derive_unless_guarded(event, check_first_append?, tail_fun, guarded) do
    if event.event_source_id in guarded do
      {:ok, event}
    else
      derive(event, check_first_append?, tail_fun)
    end
  end

  # An explicit or already-derived scope wins; the default strategy never overrides it.
  defp derive(
         %EventForEventSourceId{concurrency_scope: scope} = event,
         _check_first_append?,
         _tail_fun
       )
       when not is_nil(scope),
       do: {:ok, event}

  defp derive(%EventForEventSourceId{} = event, check_first_append?, tail_fun) do
    narrowing = [
      event_stream_type: event.event_stream_type || "",
      event_stream_id: event.event_stream_id || "",
      event_source_type: event.event_source_type || ""
    ]

    case tail_fun.(event.event_source_id, narrowing) do
      {:ok, @unavailable_sequence_number} when check_first_append? ->
        scope = ConcurrencyScope.expecting_no_matching_event([event_source_id: true] ++ narrowing)
        {:ok, %{event | concurrency_scope: scope}}

      {:ok, @unavailable_sequence_number} ->
        {:ok, event}

      {:ok, tail} ->
        {:ok, %{event | concurrency_scope: ConcurrencyScope.for_event_source(tail, narrowing)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
