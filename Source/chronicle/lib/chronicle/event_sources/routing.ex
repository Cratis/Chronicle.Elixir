# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.Routing do
  @moduledoc """
  The routing of an append that has been resolved from an event source definition.

  Resolution errors are returned as tuples so appends never send a partial request:

    * `{:unknown_event_source, reference}`
    * `{:event_stream_does_not_belong_to_event_source, source, stream}`
    * `{:event_routing_contradicts_event_source, source, dimension, expected, actual}`
  """

  alias Chronicle.EventSources.{ConcurrencyDimensions, EventSourceDefinition, EventStream}

  @enforce_keys [:definition]
  defstruct [:definition, :stream]

  @type t :: %__MODULE__{definition: EventSourceDefinition.t(), stream: EventStream.t() | nil}

  @default_stream_type "All"

  @doc "The event source name recorded as the `EventSource` metadata of the event."
  @spec event_source(t()) :: String.t()
  def event_source(%__MODULE__{definition: definition}), do: definition.name

  @doc "The event source type to write on the event."
  @spec source_type(t()) :: String.t()
  def source_type(routing), do: event_source(routing)

  @doc "The event stream type to write on the event."
  @spec stream_type(t()) :: String.t()
  def stream_type(%__MODULE__{stream: nil}), do: @default_stream_type
  def stream_type(%__MODULE__{stream: stream}), do: stream.name

  @doc "The concurrency dimensions that apply to the append."
  @spec dimensions(t()) :: ConcurrencyDimensions.t()
  def dimensions(%__MODULE__{definition: definition, stream: stream}),
    do: EventSourceDefinition.concurrency_for(definition, stream)

  @doc """
  Resolves an event source (module or name) and optional stream name against the
  registered event source modules.

  Explicit source type / stream type values that contradict the definition are
  rejected; empty, `"Default"` (source type) and `"All"` (stream type) values
  mean "not specified".
  """
  @spec resolve(
          [module()],
          module() | String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) ::
          {:ok, t()} | {:error, term()}
  def resolve(registered, reference, stream, explicit_source_type, explicit_stream_type) do
    with {:ok, definition} <- find(registered, reference),
         :ok <- check_source_type(definition, explicit_source_type),
         {:ok, stream_name} <- choose_stream(definition, stream, explicit_stream_type) do
      case stream_name do
        nil ->
          {:ok, %__MODULE__{definition: definition}}

        name ->
          case EventSourceDefinition.find_stream(definition, name) do
            nil ->
              {:error, {:event_stream_does_not_belong_to_event_source, definition.name, name}}

            event_stream ->
              {:ok, %__MODULE__{definition: definition, stream: event_stream}}
          end
      end
    end
  end

  defp find(registered, reference) do
    definitions = Enum.map(registered, & &1.__chronicle_event_source__(:definition))

    found =
      Enum.find(definitions, fn definition ->
        definition.module == reference or definition.name == reference
      end)

    case found do
      nil -> {:error, {:unknown_event_source, reference}}
      definition -> {:ok, definition}
    end
  end

  defp check_source_type(_definition, type) when type in [nil, "", "Default"], do: :ok
  defp check_source_type(%{name: name}, name), do: :ok

  defp check_source_type(%{name: name}, actual),
    do:
      {:error, {:event_routing_contradicts_event_source, name, :event_source_type, name, actual}}

  defp choose_stream(definition, stream, explicit) do
    explicit = if explicit in [nil, "", @default_stream_type], do: nil, else: explicit

    if stream != nil and explicit != nil and stream != explicit do
      {:error,
       {:event_routing_contradicts_event_source, definition.name, :event_stream_type, stream,
        explicit}}
    else
      {:ok, stream || explicit}
    end
  end
end
