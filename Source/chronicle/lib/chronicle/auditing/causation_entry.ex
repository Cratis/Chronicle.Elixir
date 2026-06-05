# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Auditing.CausationEntry do
  @moduledoc """
  Represents a single causation entry in an audit chain.
  """

  alias Chronicle.Auditing.CausationType

  @enforce_keys [:occurred, :type]
  defstruct [:occurred, :type, properties: %{}]

  @type properties :: %{optional(String.t()) => String.t()}
  @type t :: %__MODULE__{
          occurred: DateTime.t(),
          type: CausationType.t(),
          properties: properties()
        }

  @doc """
  Creates a new causation entry.
  """
  @spec new(CausationType.t() | String.t(), map()) :: t()
  def new(type, properties \\ %{}) do
    %__MODULE__{
      occurred: DateTime.utc_now(),
      type: normalize_type(type),
      properties: normalize_properties(properties)
    }
  end

  @doc """
  Returns a placeholder unknown causation entry.
  """
  @spec unknown() :: t()
  def unknown, do: new(CausationType.unknown())

  defp normalize_type(%CausationType{} = type), do: type
  defp normalize_type(type) when is_binary(type), do: CausationType.new(type)
  defp normalize_type(type) when is_atom(type), do: CausationType.new(Atom.to_string(type))

  defp normalize_properties(properties) when is_map(properties) do
    properties
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Map.new()
  end
end
