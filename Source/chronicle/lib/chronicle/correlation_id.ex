# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.CorrelationId do
  @moduledoc """
  Represents a correlation identifier for a logical operation.

  Correlation IDs tie together events and side effects that belong to the same
  operation (for example a single HTTP request).
  """

  import Bitwise

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @not_set "00000000-0000-0000-0000-000000000000"

  @doc """
  Creates a new correlation id wrapper from a string value.
  """
  @spec new(String.t()) :: t()
  def new(value) when is_binary(value), do: %__MODULE__{value: value}

  @doc """
  Creates a new random UUIDv4 correlation id.
  """
  @spec create() :: t()
  def create do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = bor(band(c, 0x0FFF), 0x4000)
    d = bor(band(d, 0x3FFF), 0x8000)

    uuid =
      [
        Integer.to_string(a, 16) |> String.pad_leading(8, "0"),
        Integer.to_string(b, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(c, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(d, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(e, 16) |> String.pad_leading(12, "0")
      ]
      |> Enum.join("-")

    new(uuid)
  end

  @doc """
  Returns the sentinel value used for an explicitly unset correlation id.
  """
  @spec not_set() :: t()
  def not_set, do: new(@not_set)
end
