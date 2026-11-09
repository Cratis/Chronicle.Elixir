# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Projections.Dictionaries do
  @moduledoc false

  # Dictionary entries for Chronicle.Testing.Projections. The kernel stores a dictionary entry under
  # the string form of its key, so the in-memory evaluator does too. Only event content keys can be
  # resolved in memory: event context and caused-by keys need the event context, which a spec does
  # not hand to Chronicle.Testing.Projections.apply_event/4.

  alias Chronicle.Projections.DictionaryKeys
  alias Chronicle.Testing.UnsupportedProjectionOperation

  @doc """
  Returns the key of the entry of `field` that `key_source` names for `event`, or `nil` when the
  event has no value there — the kernel then leaves the dictionary alone.
  """
  @spec entry(atom(), DictionaryKeys.key_source(), struct(), module()) :: String.t() | nil
  def entry(_field, {:event_content, path}, event, _read_model) do
    path
    |> path_segments()
    |> Enum.reduce(event, fn segment, value -> value && Map.get(value, segment) end)
    |> case do
      nil -> nil
      key -> to_string(key)
    end
  end

  def entry(field, key_source, _event, read_model) do
    raise UnsupportedProjectionOperation,
      read_model: read_model,
      operation:
        "a #{inspect(field)} dictionary key from #{inspect(key_source)} " <>
          "(the event context is not available in memory)"
  end

  @doc """
  Tells whether a count/increment/decrement target is a plain field or a dictionary entry.
  """
  @spec counter_target(atom() | {atom(), term()}) ::
          {:field, atom()} | {:entry, atom(), DictionaryKeys.key_source()}
  def counter_target({field, key_source}) do
    if DictionaryKeys.key_source?(key_source),
      do: {:entry, field, key_source},
      else: {:field, field}
  end

  def counter_target(field), do: {:field, field}

  @doc """
  Replaces the entry `key` of dictionary `field` with `fun.(current)`, where `current` is `nil`
  for a missing entry.
  """
  @spec update(struct(), atom(), String.t() | nil, (term() -> term())) :: struct()
  def update(instance, _field, nil, _fun), do: instance

  def update(instance, field, key, fun) do
    dictionary = Map.get(instance, field) || %{}
    Map.put(instance, field, Map.put(dictionary, key, fun.(Map.get(dictionary, key))))
  end

  @doc """
  Removes the entry `key` from dictionary `field`.
  """
  @spec remove(struct(), atom(), String.t() | nil) :: struct()
  def remove(instance, _field, nil), do: instance

  def remove(instance, field, key) do
    Map.put(instance, field, Map.delete(Map.get(instance, field) || %{}, key))
  end

  # An atom names a top-level event field. A string is the camelCase wire path, such as
  # "customer.id"; each segment maps back to the snake_case struct field.
  defp path_segments(path) when is_atom(path), do: [path]

  defp path_segments(path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
  end
end
