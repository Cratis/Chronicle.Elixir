# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.Compiler do
  @moduledoc false

  # Turns the declarations a `Chronicle.Graphs.Graph` module collected into the normalized
  # description the definition builder sends to the kernel, and refuses what cannot work with a
  # `CompileError` that points at the offending line. Everything here runs at compile time, so a
  # graph that compiles is a graph the kernel will accept.

  alias Chronicle.Serialization

  @mapping_opts [:set, :add, :subtract, :increment, :decrement, :count, :clear]
  @node_from_opts [:key, :update_only | @mapping_opts]
  @edge_from_opts [:source_key, :target_key, :identity | @mapping_opts]
  @node_removed_opts [:key, :detach]
  @edge_removed_opts [:source_key, :target_key, :identity]
  @opaque_struct_modules [DateTime, NaiveDateTime, Date, Time]
  @event_source_id "$eventSourceId"

  @doc "Validates and normalizes the declarations of the graph module compiled in `env`."
  @spec compile!(Macro.Env.t(), [map()]) :: %{nodes: [map()], edges: [map()]}
  def compile!(env, declarations) do
    nodes = for %{kind: :node} = declaration <- declarations, do: node!(env, declaration)
    reject_duplicates!(env, nodes, :label, "node label")
    edges = for %{kind: :edge} = declaration <- declarations, do: edge!(env, declaration, nodes)
    reject_duplicates!(env, edges, :type, "edge type")
    %{nodes: nodes, edges: edges}
  end

  defp reject_duplicates!(env, elements, key, what) do
    elements
    |> Enum.group_by(&Map.fetch!(&1, key))
    |> Enum.each(fn
      {_value, [_single]} ->
        :ok

      {value, [_first, second | _]} ->
        fail!(env, second.line, "#{what} #{inspect(value)} is declared more than once")
    end)
  end

  # --- nodes -----------------------------------------------------------------------------

  defp node!(env, %{module: module, opts: opts, line: line} = declaration) do
    ensure_artifact!(env, line, module, :__chronicle_graph_node__, "Chronicle.Graphs.Node")
    fields = fields!(env, line, module)
    reject_unknown_opts!(env, line, opts, [:key], "node #{inspect(module)}")

    key =
      case Keyword.fetch(opts, :key) do
        {:ok, key} when is_atom(key) and not is_nil(key) ->
          key

        _ ->
          fail!(
            env,
            line,
            "node #{inspect(module)} needs a key: name the field that identifies it, " <>
              "for example `node #{inspect(module)}, key: :id do ... end`"
          )
      end

    unless Keyword.has_key?(fields, key) do
      fail!(
        env,
        line,
        "the key #{inspect(key)} of node #{inspect(module)} is not a field of the struct"
      )
    end

    properties = properties!(env, line, module, fields)
    key_property = property_name(key)
    candidates = Enum.reject(properties, &(&1 == key_property))

    from =
      declaration.from
      |> reject_duplicate_events!(env, "from")
      |> Enum.map(&node_from!(env, &1, module, fields, candidates))

    removed_with =
      declaration.removed
      |> reject_duplicate_events!(env, "removed_with")
      |> Enum.map(&node_removed_with!(env, &1))

    %{
      module: module,
      label: module.__chronicle_graph_node__(:label),
      key: key_property,
      properties: properties,
      from: from,
      removed_with: removed_with,
      line: line
    }
  end

  defp node_from!(env, {event, opts, line}, module, fields, candidates) do
    event_fields = event_fields!(env, line, event)
    reject_unknown_opts!(env, line, opts, @node_from_opts, "from #{inspect(event)} on a node")

    explicit = explicit_properties!(env, line, module, fields, opts)

    %{
      event: event,
      key: key_expression(Keyword.get(opts, :key, :event_source_id)),
      properties: merge_properties(explicit, candidates, event_fields),
      update_only: Keyword.get(opts, :update_only, false)
    }
  end

  defp node_removed_with!(env, {event, opts, line}) do
    event_fields!(env, line, event)

    reject_unknown_opts!(
      env,
      line,
      opts,
      @node_removed_opts,
      "removed_with #{inspect(event)} on a node"
    )

    %{
      event: event,
      key: key_expression(Keyword.get(opts, :key, :event_source_id)),
      detach: Keyword.get(opts, :detach, false) == true
    }
  end

  # --- edges -----------------------------------------------------------------------------

  defp edge!(env, %{module: module, opts: opts, line: line} = declaration, nodes) do
    ensure_artifact!(env, line, module, :__chronicle_graph_edge__, "Chronicle.Graphs.Edge")
    fields = fields!(env, line, module)

    reject_unknown_opts!(
      env,
      line,
      opts,
      [:source, :target, :identified_by],
      "edge #{inspect(module)}"
    )

    source = endpoint!(env, line, module, opts, :source, nodes)
    target = endpoint!(env, line, module, opts, :target, nodes)
    identity = identity_property!(env, line, module, opts, fields)
    properties = properties!(env, line, module, fields)
    candidates = Enum.reject(properties, &(&1 == identity))

    context = %{
      module: module,
      fields: fields,
      candidates: candidates,
      identity: identity,
      identified_by: opts[:identified_by]
    }

    from =
      declaration.from
      |> reject_duplicate_events!(env, "from")
      |> Enum.map(&edge_from!(env, &1, context))

    removed_with =
      declaration.removed
      |> reject_duplicate_events!(env, "removed_with")
      |> Enum.map(&edge_removed_with!(env, &1, context))

    %{
      module: module,
      type: module.__chronicle_graph_edge__(:type),
      source: source.label,
      target: target.label,
      identity: identity,
      properties: properties,
      from: from,
      removed_with: removed_with,
      line: line
    }
  end

  defp endpoint!(env, line, module, opts, which, nodes) do
    case Keyword.fetch(opts, which) do
      {:ok, node_module} ->
        Enum.find(nodes, &(&1.module == node_module)) ||
          fail!(
            env,
            line,
            "edge #{inspect(module)} has #{which} #{inspect(node_module)}, which is not declared " <>
              "as a node of this graph: declare it with `node #{inspect(node_module)}, key: ...`"
          )

      :error ->
        fail!(env, line, "edge #{inspect(module)} needs a #{which}: the node module it connects")
    end
  end

  defp identity_property!(env, line, module, opts, fields) do
    case Keyword.get(opts, :identified_by) do
      nil ->
        nil

      field when is_atom(field) ->
        unless Keyword.has_key?(fields, field) do
          fail!(
            env,
            line,
            "identified_by #{inspect(field)} of edge #{inspect(module)} is not a field of the struct"
          )
        end

        property_name(field)

      other ->
        fail!(
          env,
          line,
          "identified_by of edge #{inspect(module)} must be a field name, got #{inspect(other)}"
        )
    end
  end

  defp edge_from!(env, {event, opts, line}, context) do
    event_fields = event_fields!(env, line, event)
    reject_unknown_opts!(env, line, opts, @edge_from_opts, "from #{inspect(event)} on an edge")
    explicit = explicit_properties!(env, line, context.module, context.fields, opts)

    %{
      event: event,
      source_key: key_expression(Keyword.get(opts, :source_key, :event_source_id)),
      target_key: key_expression(Keyword.get(opts, :target_key, :event_source_id)),
      identity: identity_expression!(env, line, event, event_fields, opts, context),
      properties: merge_properties(explicit, context.candidates, event_fields)
    }
  end

  defp edge_removed_with!(env, {event, opts, line}, context) do
    event_fields = event_fields!(env, line, event)

    if Keyword.has_key?(opts, :detach) do
      fail!(
        env,
        line,
        "removed_with #{inspect(event)} on an edge cannot detach: detach deletes the edges of " <>
          "a node, so it belongs on a node's removed_with"
      )
    end

    reject_unknown_opts!(
      env,
      line,
      opts,
      @edge_removed_opts,
      "removed_with #{inspect(event)} on an edge"
    )

    %{
      event: event,
      source_key: key_expression(Keyword.get(opts, :source_key, :event_source_id)),
      target_key: key_expression(Keyword.get(opts, :target_key, :event_source_id)),
      identity: identity_expression!(env, line, event, event_fields, opts, context)
    }
  end

  # An edge with an identifying property needs to know, for every event, which event property
  # holds it - explicitly with `identity:`, or by the event having a field of the same name.
  defp identity_expression!(env, line, event, event_fields, opts, context) do
    case {context.identity, Keyword.fetch(opts, :identity)} do
      {nil, :error} ->
        nil

      {nil, {:ok, _}} ->
        fail!(
          env,
          line,
          "identity: on #{inspect(event)} needs the edge to be declared with identified_by"
        )

      {_identity, {:ok, field}} ->
        key_expression(field)

      {identity, :error} ->
        if Map.has_key?(event_fields, identity) do
          identity
        else
          fail!(
            env,
            line,
            "edge #{inspect(context.module)} is identified by #{inspect(context.identified_by)} but " <>
              "#{inspect(event)} has no such property: name the event property with `identity:`"
          )
        end
    end
  end

  # --- shared ----------------------------------------------------------------------------

  defp ensure_artifact!(env, line, module, accessor, use_module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        unless function_exported?(module, accessor, 1) do
          fail!(env, line, "#{inspect(module)} must `use #{use_module}` to be part of a graph")
        end

      {:error, reason} ->
        fail!(
          env,
          line,
          "cannot use #{inspect(module)} in a graph: it could not be compiled (#{reason})"
        )
    end
  end

  defp fields!(env, line, module) do
    if function_exported?(module, :__info__, 1) and
         Enum.any?(module.__info__(:functions), &(&1 == {:__struct__, 0})) do
      Enum.map(struct_fields(module), &{&1.field, &1.default})
    else
      fail!(
        env,
        line,
        "#{inspect(module)} must define a struct (defstruct) to be part of a graph"
      )
    end
  end

  defp properties!(env, line, module, fields) do
    Enum.map(fields, fn {field, default} ->
      unless primitive_property?(default) do
        fail!(
          env,
          line,
          "property #{inspect(field)} of #{inspect(module)} is a nested struct or map: a graph " <>
            "property is a primitive or a list of primitives. Model the object as a node of its " <>
            "own and connect it with an edge."
        )
      end

      property_name(field)
    end)
  end

  defp primitive_property?(value) when is_list(value),
    do: Enum.all?(value, &primitive_property?/1)

  defp primitive_property?(%module{}) when module in @opaque_struct_modules, do: true

  defp primitive_property?(%module{}),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__chronicle_concept__, 1)

  defp primitive_property?(value) when is_map(value), do: false
  defp primitive_property?(_value), do: true

  defp event_fields!(env, line, event) do
    case Code.ensure_compiled(event) do
      {:module, _} ->
        unless function_exported?(event, :__chronicle_event_type__, 1) do
          fail!(
            env,
            line,
            "#{inspect(event)} is not an event type: it must `use Chronicle.Events.EventType`"
          )
        end

        if Enum.any?(event.__info__(:functions), &(&1 == {:__struct__, 0})) do
          for %{field: field, default: default} <- struct_fields(event),
              primitive_property?(default),
              into: %{},
              do: {property_name(field), field}
        else
          %{}
        end

      {:error, reason} ->
        fail!(
          env,
          line,
          "cannot use #{inspect(event)} in a graph: it could not be compiled (#{reason})"
        )
    end
  end

  defp reject_duplicate_events!(entries, env, what) do
    entries
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.each(fn
      {_event, [_single]} ->
        :ok

      {event, [_first, {_, _, line} | _]} ->
        fail!(
          env,
          line,
          "#{what} #{inspect(event)} is declared more than once on the same element"
        )
    end)

    entries
  end

  defp reject_unknown_opts!(env, line, opts, allowed, what) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      unknown ->
        fail!(
          env,
          line,
          "#{what} does not support #{Enum.map_join(Enum.uniq(unknown), ", ", &inspect/1)}; " <>
            "supported options: #{Enum.map_join(allowed, ", ", &inspect/1)}"
        )
    end
  end

  # The explicit mappings of a `from`, keyed by graph property name. The graph property names
  # are the camelCase renderings of the struct fields, as the .NET client names them.
  defp explicit_properties!(env, line, module, fields, opts) do
    property_fun = fn field ->
      unless Keyword.has_key?(fields, field) do
        fail!(env, line, "#{inspect(field)} is not a property of #{inspect(module)}")
      end

      property_name(field)
    end

    set =
      for {field, value} <- Keyword.get(opts, :set, []),
          do: {property_fun.(field), expression(value)}

    add =
      for {field, value} <- Keyword.get(opts, :add, []),
          do: {property_fun.(field), "$add(#{expression(value)})"}

    subtract =
      for {field, value} <- Keyword.get(opts, :subtract, []),
          do: {property_fun.(field), "$subtract(#{expression(value)})"}

    counters =
      for {option, expression} <- [
            increment: "$increment",
            decrement: "$decrement",
            count: "$count",
            clear: "$null"
          ],
          field <- field_names(Keyword.get(opts, option, [])),
          do: {property_fun.(field), expression}

    Map.new(set ++ add ++ subtract ++ counters)
  end

  defp field_names(value),
    do:
      value
      |> List.wrap()
      |> Enum.map(fn
        {field, _} -> field
        field -> field
      end)

  # Candidates (the properties of the element, without its key) take their explicit mapping, or
  # the event property of the same name when the event has one; explicit mappings of anything
  # else are kept as they are.
  defp merge_properties(explicit, candidates, event_fields) do
    mapped =
      for property <- candidates, into: %{} do
        cond do
          Map.has_key?(explicit, property) -> {property, Map.fetch!(explicit, property)}
          Map.has_key?(event_fields, property) -> {property, property}
          true -> {property, nil}
        end
      end
      |> Map.reject(fn {_property, expression} -> is_nil(expression) end)

    Map.merge(explicit, mapped)
  end

  # The fields of a struct module in declaration order, with their defaults.
  @doc false
  def struct_fields(module), do: List.wrap(module.__info__(:struct))

  @doc false
  def property_name(field), do: Serialization.wire_key(field, :camel)

  defp key_expression(:event_source_id), do: @event_source_id
  defp key_expression(value), do: expression(value)

  defp expression(nil), do: "$null"
  defp expression(:event_source_id), do: @event_source_id
  defp expression({:event_context, property}), do: "$eventContext(#{property_name(property)})"
  defp expression({:value, nil}), do: "$null"
  defp expression({:value, %DateTime{} = value}), do: "$value(#{DateTime.to_iso8601(value)})"
  defp expression({:value, value}), do: "$value(#{value})"
  defp expression(value) when is_boolean(value) or is_number(value), do: "$value(#{value})"
  defp expression(value) when is_atom(value), do: property_name(value)
  defp expression(value) when is_binary(value), do: value

  defp fail!(env, line, message) do
    raise CompileError, file: env.file, line: line, description: message
  end
end
