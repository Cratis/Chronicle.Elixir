# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Filter do
  @moduledoc false

  # Client-side filtering and sorting of read model structs for
  # `Chronicle.ReadModels.query/2` (see its documentation).

  @doc false
  @spec apply([struct()], keyword()) :: [struct()]
  def apply(instances, filter) when filter in [nil, []], do: instances

  def apply(instances, filter) do
    Enum.filter(instances, fn instance ->
      Enum.all?(filter, fn {field, condition} -> matches?(Map.get(instance, field), condition) end)
    end)
  end

  @doc false
  @spec sort([struct()], term()) :: [struct()]
  def sort(instances, nil), do: instances
  def sort(instances, {field, :desc}), do: Enum.sort_by(instances, &Map.get(&1, field), :desc)
  def sort(instances, {field, :asc}), do: Enum.sort_by(instances, &Map.get(&1, field), :asc)
  def sort(instances, field) when is_atom(field), do: sort(instances, {field, :asc})

  defp matches?(value, {:gt, expected}), do: compare(value, expected) == :gt
  defp matches?(value, {:gte, expected}), do: compare(value, expected) in [:gt, :eq]
  defp matches?(value, {:lt, expected}), do: compare(value, expected) == :lt
  defp matches?(value, {:lte, expected}), do: compare(value, expected) in [:lt, :eq]
  defp matches?(value, {:ne, expected}), do: value != expected
  defp matches?(value, {:in, expected}) when is_list(expected), do: value in expected

  defp matches?(value, {:contains, expected}) when is_binary(value) and is_binary(expected),
    do: String.contains?(value, expected)

  defp matches?(value, {:contains, expected}) when is_list(value), do: expected in value
  defp matches?(_value, {:contains, _expected}), do: false
  defp matches?(value, expected), do: value == expected

  defp compare(nil, _), do: :unordered
  defp compare(a, b) when a > b, do: :gt
  defp compare(a, b) when a < b, do: :lt
  defp compare(_, _), do: :eq
end
