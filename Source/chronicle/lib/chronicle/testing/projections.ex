# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Projections do
  @moduledoc """
  Evaluates the supported subset of a `Chronicle.ReadModels.ReadModel`'s embedded
  projection declarations against events, in memory — for a spec that wants to
  assert on a projected read model without a kernel to run the real projection
  engine.

  Supports `from/2` (`:set`, `:add`, `:subtract`, `:count`, `:increment`,
  `:decrement`, `:clear`) and auto-map, plus `removed_with/2`.

  `join/2`, `children/2`, `from_every/1`, `removed_with_join/2` and their
  variants need the server-side projection engine and raise
  `Chronicle.Testing.UnsupportedProjectionOperation` — point a spec at a real
  kernel through `Chronicle.Testing.Integration.setup_isolated_client/2` instead.
  """

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

    instance
    |> apply_set(event, Keyword.get(opts, :set, []), event_source_id)
    |> apply_add(event, Keyword.get(opts, :add, []), event_source_id)
    |> apply_subtract(event, Keyword.get(opts, :subtract, []), event_source_id)
    |> apply_count(Keyword.get(opts, :count))
    |> apply_increment(Keyword.get(opts, :increment, []))
    |> apply_decrement(Keyword.get(opts, :decrement, []))
    |> apply_clear(Keyword.get(opts, :clear, []))
    |> apply_auto_map(read_model_module, event, opts)
  end

  defp apply_set(instance, event, fields, event_source_id) do
    Enum.reduce(fields, instance, fn {field, expr}, instance ->
      Map.put(instance, field, resolve_expression(expr, event, event_source_id))
    end)
  end

  defp apply_add(instance, event, fields, event_source_id) do
    Enum.reduce(fields, instance, fn {field, expr}, instance ->
      value = resolve_expression(expr, event, event_source_id)
      Map.update(instance, field, value, &add_numeric(&1, value))
    end)
  end

  defp apply_subtract(instance, event, fields, event_source_id) do
    Enum.reduce(fields, instance, fn {field, expr}, instance ->
      value = resolve_expression(expr, event, event_source_id)
      Map.update(instance, field, negate(value), &add_numeric(&1, negate(value)))
    end)
  end

  defp apply_count(instance, nil), do: instance

  defp apply_count(instance, fields) do
    fields
    |> List.wrap()
    |> Enum.reduce(instance, fn field, instance ->
      Map.update(instance, field, 1, &add_numeric(&1, 1))
    end)
  end

  defp apply_increment(instance, fields) do
    Enum.reduce(fields, instance, fn {field, _expr}, instance ->
      Map.update(instance, field, 1, &add_numeric(&1, 1))
    end)
  end

  defp apply_decrement(instance, fields) do
    Enum.reduce(fields, instance, fn {field, _expr}, instance ->
      Map.update(instance, field, -1, &add_numeric(&1, -1))
    end)
  end

  defp apply_clear(instance, fields) do
    fields
    |> List.wrap()
    |> Enum.reduce(instance, fn field, instance -> Map.put(instance, field, nil) end)
  end

  # Mirrors the kernel's own AutoMap rule: matching field names are copied from the event
  # unless a :set/:add/:subtract/:count/:increment/:decrement/:clear mapping already set them,
  # or the field is excluded via :no_auto_map.
  defp apply_auto_map(instance, read_model_module, event, opts) do
    {auto_map, excluded} = read_model_module.__chronicle_read_model__(:no_auto_map)
    explicit = Enum.flat_map([:set, :add, :subtract, :clear], &Keyword.get(opts, &1, []))
    explicit_fields = MapSet.new(explicit, fn {field, _expr} -> field end)
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

  defp resolve_expression(:event_source_id, _event, event_source_id), do: event_source_id

  defp resolve_expression(expr, event, _event_source_id) when is_atom(expr),
    do: Map.get(event, expr)

  defp resolve_expression(value, _event, _event_source_id), do: value

  defp add_numeric(nil, value), do: value

  defp add_numeric(current, value) when is_number(current) and is_number(value),
    do: current + value

  defp add_numeric(current, _value), do: current

  defp negate(value) when is_number(value), do: -value
  defp negate(value), do: value
end
