# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Projections do
  @moduledoc """
  Evaluates the supported subset of a `Chronicle.ReadModels.ReadModel`'s embedded
  projection declarations against events, in memory — for a spec that wants to
  assert on a projected read model without a kernel to run the real projection
  engine.

  Supports `from/2` (`:set`, `:set_once`, `:add`, `:subtract`, `:count`,
  `:increment`, `:decrement`, `:remove`, `:clear`) and auto-map, plus
  `removed_with/2`. Dictionary entries keyed by `{:event_content, property}` are
  evaluated; keys and values from the event context (`{:event_context, _}`,
  `{:caused_by, _}`) raise
  `Chronicle.Testing.UnsupportedProjectionOperation`, since `apply_event/4` has
  no event context.

  `join/2`, `children/2`, `from_every/1`, `removed_with_join/2` and their
  variants need the server-side projection engine and raise
  `Chronicle.Testing.UnsupportedProjectionOperation` — point a spec at a real
  kernel through `Chronicle.Testing.Integration.setup_isolated_client/2` instead.
  """

  alias Chronicle.Testing.Projections.Dictionaries
  alias Chronicle.Testing.UnsupportedProjectionOperation

  @doc """
  Applies `event` (appended for `event_source_id`) to `instance` (or `nil`, for a
  new instance) according to `read_model_module`'s `from/2` and `removed_with/2`
  declarations.

  Returns `{:ok, instance}`, `{:ok, nil}` when no `from/2` matches the event (the
  instance is returned unchanged), or `:removed` when a `removed_with/2` matches.
  """
  @spec apply_event(module(), struct() | nil, struct(), String.t()) ::
          {:ok, struct() | nil} | :removed
  def apply_event(read_model_module, instance, event, event_source_id \\ nil) do
    ensure_supported!(read_model_module)
    event_module = event.__struct__

    cond do
      matches?(read_model_module, :removed_with, event_module) ->
        :removed

      opts = matching_opts(read_model_module, :from, event_module) ->
        {:ok, apply_from(read_model_module, instance, event, opts, event_source_id)}

      true ->
        {:ok, instance}
    end
  end

  defp ensure_supported!(read_model_module) do
    Enum.each(
      [
        join: :join,
        removed_with_join: :removed_with_join,
        children: :children,
        from_every: :from_every
      ],
      fn {key, operation} ->
        if read_model_module.__chronicle_read_model__(key) != [] do
          raise UnsupportedProjectionOperation,
            read_model: read_model_module,
            operation: operation
        end
      end
    )
  end

  defp matches?(read_model_module, declaration, event_module) do
    read_model_module.__chronicle_read_model__(declaration)
    |> Enum.any?(fn {module, _opts} -> module == event_module end)
  end

  defp matching_opts(read_model_module, declaration, event_module) do
    read_model_module.__chronicle_read_model__(declaration)
    |> Enum.find(fn {module, _opts} -> module == event_module end)
    |> case do
      nil -> nil
      {_module, opts} -> opts
    end
  end

  defp apply_from(read_model_module, instance, event, opts, event_source_id) do
    instance = instance || struct(read_model_module)
    resolve = &resolve_expression(&1, event, event_source_id, read_model_module)
    entry = &Dictionaries.entry(&1, &2, event, read_model_module)

    instance
    |> apply_values(Keyword.get(opts, :set, []), entry, resolve, fn _current, value -> value end)
    |> apply_values(Keyword.get(opts, :set_once, []), entry, resolve, &set_once/2)
    |> apply_values(Keyword.get(opts, :add, []), entry, resolve, &add_numeric/2)
    |> apply_values(
      Keyword.get(opts, :subtract, []),
      entry,
      resolve,
      &add_numeric(&1, negate(&2))
    )
    |> apply_counter(Keyword.get(opts, :count) |> List.wrap(), entry, 1)
    |> apply_counter(Keyword.get(opts, :increment, []), entry, 1)
    |> apply_counter(Keyword.get(opts, :decrement, []), entry, -1)
    |> apply_remove(Keyword.get(opts, :remove, []), entry)
    |> apply_clear(Keyword.get(opts, :clear, []))
    |> apply_auto_map(read_model_module, event, opts)
  end

  # Applies `combine.(current, value)` to every target of a set/set_once/add/subtract list. A target
  # is a property, or one entry of a dictionary property for an {:entry, key_source, expression}.
  defp apply_values(instance, fields, entry, resolve, combine) do
    Enum.reduce(fields, instance, fn
      {field, {:entry, key_source, expr}}, instance ->
        key = entry.(field, key_source)
        Dictionaries.update(instance, field, key, &combine.(&1, resolve.(expr)))

      {field, expr}, instance ->
        Map.put(instance, field, combine.(Map.get(instance, field), resolve.(expr)))
    end)
  end

  defp apply_counter(instance, fields, entry, step) do
    Enum.reduce(fields, instance, fn field_or_pair, instance ->
      case Dictionaries.counter_target(field_or_pair) do
        {:entry, field, key_source} ->
          Dictionaries.update(instance, field, entry.(field, key_source), &add_numeric(&1, step))

        {:field, field} ->
          Map.update(instance, field, step, &add_numeric(&1, step))
      end
    end)
  end

  defp apply_remove(instance, fields, entry) do
    Enum.reduce(fields, instance, fn {field, key_source}, instance ->
      Dictionaries.remove(instance, field, entry.(field, key_source))
    end)
  end

  defp apply_clear(instance, fields) do
    fields
    |> List.wrap()
    |> Enum.reduce(instance, fn field, instance -> Map.put(instance, field, nil) end)
  end

  defp set_once(nil, value), do: value
  defp set_once(current, _value), do: current

  # Mirrors the kernel's own AutoMap rule: matching field names are copied from the event
  # unless a :set/:add/:subtract/:count/:increment/:decrement/:clear mapping already set them,
  # or the field is excluded via :no_auto_map.
  defp apply_auto_map(instance, read_model_module, event, opts) do
    {auto_map, excluded} = read_model_module.__chronicle_read_model__(:no_auto_map)

    explicit =
      Enum.flat_map([:set, :set_once, :add, :subtract, :remove, :clear], fn operation ->
        opts |> Keyword.get(operation, []) |> List.wrap()
      end)

    explicit_fields =
      MapSet.new(explicit, fn
        {field, _expr} -> field
        field -> field
      end)

    excluded = MapSet.new(excluded)

    if auto_map == :disabled do
      instance
    else
      model_fields =
        instance.__struct__.__struct__() |> Map.keys() |> List.delete(:__struct__) |> MapSet.new()

      event_fields = event.__struct__.__struct__() |> Map.keys() |> List.delete(:__struct__)

      event_fields
      |> Enum.filter(&MapSet.member?(model_fields, &1))
      |> Enum.reject(&(MapSet.member?(explicit_fields, &1) or MapSet.member?(excluded, &1)))
      |> Enum.reduce(instance, fn field, instance ->
        Map.put(instance, field, Map.get(event, field))
      end)
    end
  end

  defp resolve_expression(:event_source_id, _event, event_source_id, _read_model),
    do: event_source_id

  defp resolve_expression(expr, _event, _event_source_id, read_model)
       when is_tuple(expr) and elem(expr, 0) == :caused_by do
    raise UnsupportedProjectionOperation,
      read_model: read_model,
      operation: "#{inspect(expr)} (the event context is not available in memory)"
  end

  defp resolve_expression(expr, event, _event_source_id, _read_model) when is_atom(expr),
    do: Map.get(event, expr)

  defp resolve_expression(value, _event, _event_source_id, _read_model), do: value

  defp add_numeric(nil, value), do: value

  defp add_numeric(current, value) when is_number(current) and is_number(value),
    do: current + value

  defp add_numeric(current, _value), do: current

  defp negate(value) when is_number(value), do: -value
  defp negate(value), do: value
end
