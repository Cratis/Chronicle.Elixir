# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.ConcurrencyDimensions do
  @moduledoc """
  The dimensions of an append that take part in its concurrency check.

  Written as a list of atoms — `:event_source_id`, `:event_source_type`,
  `:event_stream_type`, `:event_stream_id` — or `:none` / `[]` for no
  dimensions. The wire representation is the flags value of the Chronicle
  `ConcurrencyDimensions` contract.
  """

  import Bitwise

  @flags [event_source_id: 1, event_source_type: 2, event_stream_type: 4, event_stream_id: 8]

  @type dimension :: :event_source_id | :event_source_type | :event_stream_type | :event_stream_id
  @type t :: [dimension()]

  @doc "Normalizes dimensions given as atoms, a list of atoms, or a flags integer into a sorted list."
  @spec normalize(:none | dimension() | [dimension()] | non_neg_integer() | nil) :: t()
  def normalize(nil), do: []
  def normalize(:none), do: []
  def normalize(value) when is_atom(value), do: normalize([value])

  def normalize(value) when is_integer(value) and value >= 0 do
    for {name, flag} <- @flags, (value &&& flag) != 0, do: name
  end

  def normalize(values) when is_list(values) do
    Enum.each(values, fn value ->
      unless Keyword.has_key?(@flags, value) do
        raise ArgumentError,
              "unknown concurrency dimension #{inspect(value)}, expected one of #{inspect(Keyword.keys(@flags))}"
      end
    end)

    for {name, _flag} <- @flags, name in values, do: name
  end

  @doc "Returns the flags integer sent on the wire."
  @spec to_flags(:none | dimension() | [dimension()] | non_neg_integer() | nil) ::
          non_neg_integer()
  def to_flags(value) do
    value
    |> normalize()
    |> Enum.reduce(0, fn name, acc -> acc ||| Keyword.fetch!(@flags, name) end)
  end
end
