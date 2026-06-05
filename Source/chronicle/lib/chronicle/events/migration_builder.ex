# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.MigrationBuilder do
  @moduledoc """
  Fluent builder for event migration property transformations.

  The builder produces the JMESPath-compatible JSON fragments Chronicle expects
  when registering event type migrations.
  """

  @split_expression "$split"
  @combine_expression "$combine"
  @rename_expression "$rename"
  @default_value_expression "$defaultValue"

  @enforce_keys [:properties]
  defstruct properties: %{}

  @type property_name :: atom() | String.t()
  @type t :: %__MODULE__{properties: map()}

  @doc """
  Creates an empty migration builder.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{properties: %{}}

  @doc """
  Copies a property unchanged.

  Since Chronicle preserves unspecified properties automatically, the single
  argument form is a no-op that keeps pipeline code expressive.
  """
  @spec copy_property(t(), property_name()) :: t()
  def copy_property(%__MODULE__{} = builder, _property), do: builder

  @doc """
  Copies a property from one name to another.
  """
  @spec copy_property(t(), property_name(), property_name()) :: t()
  def copy_property(%__MODULE__{} = builder, source_property, target_property),
    do: rename_property(builder, source_property, target_property)

  @doc """
  Renames a property from `source_property` to `target_property`.
  """
  @spec rename_property(t(), property_name(), property_name()) :: t()
  def rename_property(%__MODULE__{} = builder, source_property, target_property) do
    put_property(builder, target_property, %{
      @rename_expression => normalize_property_name(source_property)
    })
  end

  @doc """
  Alias for `rename_property/3` with the target property first.
  """
  @spec renamed_from(t(), property_name(), property_name()) :: t()
  def renamed_from(%__MODULE__{} = builder, target_property, source_property),
    do: rename_property(builder, source_property, target_property)

  @doc """
  Sets a default value for a property.
  """
  @spec default_value(t(), property_name(), term()) :: t()
  def default_value(%__MODULE__{} = builder, target_property, value) do
    put_property(builder, target_property, %{@default_value_expression => value})
  end

  @doc """
  Alias for `default_value/3`.
  """
  @spec set_property(t(), property_name(), term()) :: t()
  def set_property(%__MODULE__{} = builder, target_property, value),
    do: default_value(builder, target_property, value)

  @doc """
  Splits a source property and maps one part to a target property.
  """
  @spec split_property(t(), property_name(), property_name(), String.t(), non_neg_integer()) ::
          t()
  def split_property(%__MODULE__{} = builder, source_property, target_property, separator, part) do
    put_property(builder, target_property, %{
      @split_expression => %{
        "source" => normalize_property_name(source_property),
        "separator" => separator,
        "part" => part
      }
    })
  end

  @doc """
  Combines multiple source properties into a target property.
  """
  @spec combine_properties(t(), [property_name()], property_name(), String.t()) :: t()
  def combine_properties(%__MODULE__{} = builder, source_properties, target_property, separator)
      when is_list(source_properties) do
    put_property(builder, target_property, %{
      @combine_expression => %{
        "sources" => Enum.map(source_properties, &normalize_property_name/1),
        "separator" => separator
      }
    })
  end

  @doc """
  Returns the builder as a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{properties: properties}), do: properties

  @doc """
  Returns the builder as JSON.
  """
  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = builder), do: builder |> to_map() |> Jason.encode!()

  defp put_property(%__MODULE__{properties: properties} = builder, target_property, expression) do
    %{
      builder
      | properties: Map.put(properties, normalize_property_name(target_property), expression)
    }
  end

  defp normalize_property_name(property) when is_atom(property),
    do: property |> Atom.to_string() |> snake_to_camel()

  defp normalize_property_name(property) when is_binary(property) do
    if String.contains?(property, "_") do
      snake_to_camel(property)
    else
      property
    end
  end

  defp snake_to_camel(snake) do
    [head | tail] = String.split(snake, "_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end
end
