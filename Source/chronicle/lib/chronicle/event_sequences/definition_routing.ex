# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.DefinitionRouting do
  @moduledoc false

  # Applies event source definitions to buffered appends: resolves the source /
  # stream routing of every event (per event, so mixed-source batches work), and
  # derives a concurrency scope from the definition's dimensions for event
  # sources that gave no explicit scope. Nothing is sent until every event
  # resolved, so a rejected routing never leaves a partial append.

  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.EventSources.Routing

  @unavailable_sequence_number 18_446_744_073_709_551_615

  @spec used?([EventForEventSourceId.t()]) :: boolean()
  def used?(events), do: Enum.any?(events, &(&1.event_source != nil or &1.event_stream != nil))

  @doc "Fills event entries that name no source/stream from batch-level defaults."
  @spec apply_defaults([EventForEventSourceId.t()], keyword()) :: [EventForEventSourceId.t()]
  def apply_defaults(events, opts) do
    source = Keyword.get(opts, :event_source)
    stream = Keyword.get(opts, :event_stream)

    Enum.map(events, fn
      %EventForEventSourceId{event_source: nil} = event ->
        %{event | event_source: source, event_stream: event.event_stream || stream}

      event ->
        event
    end)
  end

  @spec resolve([EventForEventSourceId.t()], [module()]) ::
          {:ok, [EventForEventSourceId.t()]} | {:error, term()}
  def resolve(events, registered) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case resolve_event(event, registered) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp resolve_event(%EventForEventSourceId{event_source: nil, event_stream: nil} = event, _),
    do: {:ok, event}

  defp resolve_event(%EventForEventSourceId{event_source: nil, event_stream: stream}, _),
    do: {:error, {:event_stream_without_event_source, stream}}

  defp resolve_event(%EventForEventSourceId{} = event, registered) do
    with {:ok, routing} <-
           Routing.resolve(
             registered,
             event.event_source,
             event.event_stream,
             event.event_source_type,
             event.event_stream_type
           ) do
      {:ok,
       %{
         event
         | event_source_type: Routing.source_type(routing),
           event_stream_type: Routing.stream_type(routing),
           routing: routing
       }}
    end
  end

  @doc """
  Derives concurrency scopes from definition dimensions. `tail_fun` is called as
  `tail_fun.(event_source_id_or_nil, narrowing_opts)` and returns the tail
  sequence number. An explicit scope on any event of an event source wins.
  """
  @spec apply_concurrency([EventForEventSourceId.t()], function()) ::
          {:ok, [EventForEventSourceId.t()]} | {:error, term()}
  def apply_concurrency(events, tail_fun) do
    explicit =
      for %{concurrency_scope: scope, event_source_id: id} <- events,
          scope != nil,
          into: MapSet.new(),
          do: id

    events
    |> Enum.reduce_while({:ok, [], explicit}, fn event, {:ok, acc, done} ->
      if applies?(event, done) do
        case derive_scope(event, tail_fun) do
          {:ok, scope} ->
            {:cont,
             {:ok, [%{event | concurrency_scope: scope} | acc],
              MapSet.put(done, event.event_source_id)}}

          {:error, _} = error ->
            {:halt, error}
        end
      else
        {:cont, {:ok, [event | acc], done}}
      end
    end)
    |> case do
      {:ok, result, _} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp applies?(%{routing: nil}, _done), do: false

  defp applies?(%{routing: routing, event_source_id: id}, done),
    do: Routing.dimensions(routing) != [] and not MapSet.member?(done, id)

  # Reads the tail with exactly the narrowing the scope declares: the kernel
  # validates the append against that, so both must ask the same question.
  defp derive_scope(%{routing: routing} = event, tail_fun) do
    dimensions = Routing.dimensions(routing)
    by_source_id? = :event_source_id in dimensions
    source_type = if :event_source_type in dimensions, do: Routing.source_type(routing), else: ""
    stream_type = if :event_stream_type in dimensions, do: Routing.stream_type(routing), else: ""
    stream_id = if :event_stream_id in dimensions, do: event.event_stream_id || "", else: ""

    narrowing = [
      event_source_type: source_type,
      event_stream_type: stream_type,
      event_stream_id: stream_id
    ]

    case tail_fun.(if(by_source_id?, do: event.event_source_id), narrowing) do
      {:ok, tail} ->
        {:ok,
         ConcurrencyScope.new(
           if(is_integer(tail), do: tail, else: @unavailable_sequence_number),
           [event_source_id: by_source_id?] ++ narrowing
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
