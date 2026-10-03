# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.EventSource do
  @moduledoc """
  Declares an event source definition.

  An event source gives appends a stable name, optional streams and default
  concurrency dimensions. Routing belongs to the append, not to event types: the
  same event type can be appended through different event sources.

      defmodule MyApp.AccountEventSource do
        use Chronicle.EventSources.EventSource,
          name: "Account",
          description: "A bank account",
          concurrency: [:event_source_id]

        stream "Transactions",
          description: "Money movements",
          concurrency: [:event_source_id, :event_stream_id]
      end

  Definitions are discovered like event types and registered with the event store
  at startup. Append through one with the `:event_source` and `:event_stream`
  options of `Chronicle.append/3` and friends. Without a definition appends behave
  exactly as before.

  Omit `:name` to use the module's last segment without a trailing `EventSource`.
  """

  defmacro __using__(opts) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description, "")
    concurrency = Keyword.get(opts, :concurrency, [])

    quote do
      import Chronicle.EventSources.EventSource, only: [stream: 1, stream: 2]
      Module.register_attribute(__MODULE__, :chronicle_event_streams, accumulate: true)
      @chronicle_event_source_name unquote(name)
      @chronicle_event_source_description unquote(description)
      @chronicle_event_source_concurrency unquote(concurrency)
      @before_compile Chronicle.EventSources.EventSource
    end
  end

  @doc """
  Declares a named stream of the event source.

  Options: `:description` and `:concurrency` (dimensions, see
  `Chronicle.EventSources.ConcurrencyDimensions`).
  """
  defmacro stream(name, opts \\ []) do
    quote do
      @chronicle_event_streams {unquote(name), unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    module = env.module
    streams = module |> Module.get_attribute(:chronicle_event_streams) |> Enum.reverse()

    definition =
      Chronicle.EventSources.EventSource.build_definition(
        module,
        Module.get_attribute(module, :chronicle_event_source_name),
        Module.get_attribute(module, :chronicle_event_source_description),
        Module.get_attribute(module, :chronicle_event_source_concurrency),
        streams
      )

    escaped = Macro.escape(definition)

    quote do
      @doc false
      def __chronicle_event_source__(:definition), do: unquote(escaped)
      def __chronicle_event_source__(:name), do: unquote(escaped).name
    end
  end

  @doc false
  def build_definition(module, name, description, concurrency, streams) do
    alias Chronicle.EventSources.{ConcurrencyDimensions, EventSourceDefinition, EventStream}

    names = Enum.map(streams, &elem(&1, 0))

    case names -- Enum.uniq(names) do
      [] ->
        :ok

      [duplicate | _] ->
        raise Chronicle.EventSources.DuplicateEventStreamName,
          event_source: inspect(module),
          stream: duplicate
    end

    Enum.each(names, fn stream_name ->
      unless is_binary(stream_name) and stream_name != "" do
        raise ArgumentError,
              "stream names must be non-empty strings, got: #{inspect(stream_name)}"
      end
    end)

    %EventSourceDefinition{
      module: module,
      name: name || default_name(module),
      description: description,
      concurrency: ConcurrencyDimensions.normalize(concurrency),
      streams:
        Enum.map(streams, fn {stream_name, opts} ->
          %EventStream{
            name: stream_name,
            description: Keyword.get(opts, :description, ""),
            concurrency: ConcurrencyDimensions.normalize(Keyword.get(opts, :concurrency, []))
          }
        end)
    }
  end

  defp default_name(module) do
    last = module |> Module.split() |> List.last()

    if String.length(last) > 11 and String.ends_with?(last, "EventSource"),
      do: String.replace_suffix(last, "EventSource", ""),
      else: last
  end
end
