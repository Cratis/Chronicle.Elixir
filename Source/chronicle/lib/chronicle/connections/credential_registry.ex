# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CredentialRegistry do
  @moduledoc false

  # The credential values this node currently authenticates with, kept only so the crash
  # report filter can scrub them out of free-form log text as a defense in depth. The values
  # are never logged or inspected here, and the list is bounded: the newest values win, so a
  # rotating OAuth token cannot grow it without limit. Short values are ignored because
  # scrubbing them would mangle unrelated log text.

  @key {__MODULE__, :values}
  @capacity 16
  @min_length 8

  @spec remember(term()) :: :ok
  def remember(value) when is_binary(value) and byte_size(value) >= @min_length do
    current = values()

    unless value in current do
      :persistent_term.put(@key, Enum.take([value | current], @capacity))
    end

    :ok
  end

  def remember(_value), do: :ok

  @spec forget(term()) :: :ok
  def forget(value) do
    case values() do
      [] ->
        :ok

      current ->
        remaining = List.delete(current, value)
        if remaining != current, do: :persistent_term.put(@key, remaining)
        :ok
    end
  end

  @spec values() :: [binary()]
  def values, do: :persistent_term.get(@key, [])
end
