# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.EventSourceDefinition do
  @moduledoc """
  A discovered event source definition: stable name, description, default
  concurrency dimensions and streams.

  The name is the event source type written on appended events and the
  `EventSource` metadata recorded on them.
  """

  alias Chronicle.EventSources.{ConcurrencyDimensions, EventStream}

  @enforce_keys [:module, :name]
  defstruct [:module, :name, description: "", concurrency: [], streams: []]

  @type t :: %__MODULE__{
          module: module(),
          name: String.t(),
          description: String.t(),
          concurrency: ConcurrencyDimensions.t(),
          streams: [EventStream.t()]
        }

  @doc "Finds a stream by name."
  @spec find_stream(t(), String.t()) :: EventStream.t() | nil
  def find_stream(%__MODULE__{streams: streams}, name), do: Enum.find(streams, &(&1.name == name))

  @doc """
  Returns the dimensions that apply to an append: those of the stream when one
  is given and declares any, otherwise those of the event source.
  """
  @spec concurrency_for(t(), EventStream.t() | nil) :: ConcurrencyDimensions.t()
  def concurrency_for(%__MODULE__{concurrency: concurrency}, nil), do: concurrency

  def concurrency_for(%__MODULE__{concurrency: concurrency}, %EventStream{concurrency: []}),
    do: concurrency

  def concurrency_for(%__MODULE__{}, %EventStream{concurrency: concurrency}), do: concurrency
end
