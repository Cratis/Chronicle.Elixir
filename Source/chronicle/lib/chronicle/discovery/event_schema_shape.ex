# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.EventSchemaShape do
  @moduledoc """
  Extracts a canonical, coarse shape from an event's JSON schema for identity comparison.

  A faithful port of the .NET client's `EventSchemaShape` normalization
  (`Source/Clients/DotNET/Discovery/EventSchemaShape.cs`): property names, nesting and
  primitive type categories, with `$ref`/`anyOf`/`oneOf` resolved and nullability stripped —
  so renaming a property is a shape change but reordering keys, widening `integer` to
  `number`, or `["string", "null"]` versus `"string"` is not. Used by
  `Chronicle.Discovery.DriftDetector` to notice a generation whose struct changed without a
  bumped `:generation`.
  """

  @max_depth 64

  @doc """
  Normalizes a nonempty JSON schema string for identity comparison.

  Returns the canonical shape as a normalized map (comparable with `==`), or `nil` when the
  schema isn't a JSON object, has no properties, or normalization is unsafe (an unresolved or
  cyclic `$ref`).
  """
  @spec of(String.t()) :: map() | nil
  def of(schema) when is_binary(schema) do
    case Jason.decode(schema) do
      {:ok, %{} = root} ->
        case normalize(root, root, 0) do
          %{"properties" => properties} = shape when map_size(properties) > 0 -> shape
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def of(_schema), do: nil

  defp normalize(_node, _root, depth) when depth > @max_depth, do: nil

  defp normalize(%{"$ref" => reference}, root, depth) do
    case resolve(reference, root) do
      nil -> nil
      target -> normalize(target, root, depth + 1)
    end
  end

  defp normalize(%{"anyOf" => alternatives}, root, depth) when is_list(alternatives),
    do: normalize_alternatives(alternatives, root, depth)

  defp normalize(%{"oneOf" => alternatives}, root, depth) when is_list(alternatives),
    do: normalize_alternatives(alternatives, root, depth)

  defp normalize(%{} = node, root, depth) do
    base = %{"type" => node |> types_of() |> Enum.join("|")}

    with {:ok, with_properties} <- add_properties(node, base, root, depth),
         {:ok, with_items} <- add_child(node, "items", with_properties, root, depth),
         {:ok, complete} <- add_child(node, "additionalProperties", with_items, root, depth) do
      complete
    else
      :error -> nil
    end
  end

  defp normalize(_node, _root, _depth), do: nil

  defp types_of(node) do
    types =
      case Map.get(node, "type") do
        list when is_list(list) -> list
        value when is_binary(value) -> [value]
        _ -> if Map.has_key?(node, "properties"), do: ["object"], else: []
      end

    types
    |> Enum.reject(&(&1 == "null"))
    |> Enum.map(&if(&1 == "integer", do: "number", else: &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp resolve("#/" <> rest, root) do
    rest
    |> String.split("/")
    |> Enum.reduce_while(root, fn segment, node ->
      key = segment |> String.replace("~1", "/") |> String.replace("~0", "~")

      case node do
        %{} ->
          case Map.fetch(node, key) do
            {:ok, next} -> {:cont, next}
            :error -> {:halt, nil}
          end

        _ ->
          {:halt, nil}
      end
    end)
    |> case do
      %{} = map -> map
      _ -> nil
    end
  end

  defp resolve(_reference, _root), do: nil

  defp normalize_alternatives(alternatives, root, depth) do
    variants =
      alternatives
      |> Enum.filter(&(is_map(&1) and Map.get(&1, "type") != "null"))
      |> Enum.map(&normalize(&1, root, depth + 1))

    cond do
      variants == [] or Enum.any?(variants, &is_nil/1) ->
        nil

      length(variants) == 1 ->
        hd(variants)

      true ->
        distinct =
          variants
          |> Enum.map(&Jason.encode!/1)
          |> Enum.uniq()
          |> Enum.sort()

        %{"variants" => distinct}
    end
  end

  defp add_properties(node, result, root, depth) do
    case Map.get(node, "properties") do
      nil ->
        {:ok, result}

      %{} = properties ->
        properties
        |> Enum.sort_by(fn {key, _value} -> key end)
        |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
          case value do
            %{} ->
              case normalize(value, root, depth + 1) do
                nil -> {:halt, :error}
                shape -> {:cont, {:ok, Map.put(acc, key, shape)}}
              end

            _ ->
              {:halt, :error}
          end
        end)
        |> case do
          {:ok, normalized} -> {:ok, Map.put(result, "properties", normalized)}
          :error -> :error
        end

      _ ->
        {:ok, result}
    end
  end

  defp add_child(node, key, result, root, depth) do
    case Map.get(node, key) do
      %{} = child ->
        case normalize(child, root, depth + 1) do
          nil -> :error
          shape -> {:ok, Map.put(result, key, shape)}
        end

      _ ->
        {:ok, result}
    end
  end
end
