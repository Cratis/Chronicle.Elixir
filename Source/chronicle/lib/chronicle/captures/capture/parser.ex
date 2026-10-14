# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.Capture.Parser do
  @moduledoc false

  # Walks the raw (unexpanded) AST of `do` blocks used by the capture DSL
  # (`map`, `append`, `nested`, `children`). Statements inside those blocks are
  # never macro-expanded — they are pattern-matched as plain syntax, the same
  # technique `Chronicle.Projections.Children` uses for nested `children` blocks.

  alias Chronicle.Captures.{MissingAppendCondition, TargetPropertyMustBeAProperty}
  alias Chronicle.Serialization

  @doc "Splits a `do` block into its individual statements."
  @spec block_statements(Macro.t()) :: [Macro.t()]
  def block_statements({:__block__, _, statements}), do: statements
  def block_statements(nil), do: []
  def block_statements(statement), do: [statement]

  @doc "Parses the statements of a `map do ... end` block into map operations."
  @spec map_operations(Macro.t()) :: [Chronicle.Captures.Declaration.map_operation()]
  def map_operations(block) do
    block |> block_statements() |> Enum.map(&map_operation/1)
  end

  @doc """
  Builds an append definition from an `append` call's event module, options and `do` block,
  resolving `event_module_ast` in `env`.
  """
  @spec build_append(Macro.t(), Macro.t(), Macro.t(), Macro.Env.t()) ::
          Chronicle.Captures.Declaration.append()
  def build_append(event_module_ast, opts_ast, block_ast, env) do
    event_module = Macro.expand(event_module_ast, env)
    opts = eval_literal(opts_ast)

    when_clause =
      case Keyword.get(opts, :when) do
        nil -> raise MissingAppendCondition, event_type: event_module
        clause -> normalize_when(clause)
      end

    assignments = block_ast |> block_statements() |> Enum.map(&set_assignment(&1, event_module))

    {validate_append_event_type!(event_type_id(event_module), event_module), when_clause,
     assignments}
  end

  @doc """
  Parses a `nested`/`children` scope body (an optional `map` block and any number of `append`
  blocks) into `{map_operations_or_nil, appends}`.
  """
  @spec parse_scope(Macro.t(), Macro.Env.t()) ::
          {[Chronicle.Captures.Declaration.map_operation()] | nil,
           [Chronicle.Captures.Declaration.append()]}
  def parse_scope(block, env) do
    {map_ops, appends} =
      block
      |> block_statements()
      |> Enum.reduce({nil, []}, fn statement, {map_acc, appends_acc} ->
        parse_scope_statement(statement, env, map_acc, appends_acc)
      end)

    {map_ops, Enum.reverse(appends)}
  end

  defp parse_scope_statement({:map, _, [[do: map_block]]}, _env, _map_acc, appends_acc) do
    {map_operations(map_block), appends_acc}
  end

  defp parse_scope_statement(
         {:append, _, [event_module_ast, [do: set_block]]},
         env,
         map_acc,
         appends_acc
       ) do
    append = build_append(event_module_ast, [], set_block, env)
    {map_acc, [append | appends_acc]}
  end

  defp parse_scope_statement(
         {:append, _, [event_module_ast, opts_ast, [do: set_block]]},
         env,
         map_acc,
         appends_acc
       ) do
    append = build_append(event_module_ast, opts_ast, set_block, env)
    {map_acc, [append | appends_acc]}
  end

  defp parse_scope_statement(other, _env, _map_acc, _appends_acc) do
    raise ArgumentError,
          "unsupported statement in a capture scope block: #{Macro.to_string(other)}; " <>
            "expected map/1 or append/2,3"
  end

  defp normalize_when(property) when is_binary(property), do: {:property, property}
  defp normalize_when(clause), do: clause

  defp set_assignment({:set, _, [target, source_expression]}, event_module)
       when is_atom(target) do
    unless struct_has_field?(event_module, target) do
      raise TargetPropertyMustBeAProperty, event_type: event_module, property: target
    end

    {Serialization.wire_key(target, :camel), eval_literal(source_expression)}
  end

  defp set_assignment(other, _event_module) do
    raise ArgumentError,
          "expected set(:field, \"source expression\") inside an append block, got: " <>
            Macro.to_string(other)
  end

  defp struct_has_field?(event_module, field) do
    Code.ensure_compiled(event_module)

    function_exported?(event_module, :__struct__, 0) and
      Map.has_key?(event_module.__struct__(), field)
  rescue
    _ -> false
  end

  @doc """
  Resolves a Chronicle event type module to its registered event type id.
  """
  @spec event_type_id(module()) :: String.t()
  def event_type_id(event_module) do
    Code.ensure_compiled(event_module)

    unless function_exported?(event_module, :__chronicle_event_type__, 1) do
      raise ArgumentError,
            "#{inspect(event_module)} is not a Chronicle event type (use Chronicle.Events.EventType)"
    end

    event_module.__chronicle_event_type__(:id)
  end

  # The kernel's CDL parser lexes the target of "append <EventType>" as a type-name token that
  # must start with an uppercase letter (confirmed against a real kernel: a lowercase-leading
  # id, with or without a hyphen, fails "Invalid append declaration '...' - expected 'append
  # <EventType>'"; the published grammar's plain Identifier production doesn't show this). `from`
  # (an events source) has no such restriction - it is free-form text in the real grammar - so
  # this check only guards an append target.
  @append_event_type ~r/^[A-Z][A-Za-z0-9_]*$/

  defp validate_append_event_type!(id, event_module) do
    unless Regex.match?(@append_event_type, id) do
      raise ArgumentError,
            "the registered event type id #{inspect(id)} of #{inspect(event_module)} cannot be an " <>
              "append target: the kernel's CDL parser requires an append's event type to start " <>
              "with an uppercase letter and contain only letters, digits, or underscores (no " <>
              "hyphens). Register this event type with an id matching that shape to append it " <>
              "from a capture."
    end

    id
  end

  defp map_operation({:rename, _, [target, source]}) do
    {:rename, to_path(target), to_path(source)}
  end

  defp map_operation({:template, _, [target, template]}) do
    {:template, to_path(target), eval_literal(template)}
  end

  defp map_operation({:translate, _, [target, source, entries]}) do
    pairs =
      entries |> eval_literal() |> Enum.map(fn {from, to} -> {to_string(from), to_string(to)} end)

    {:translate, to_path(target), to_path(source), pairs}
  end

  defp map_operation({:split, _, [source, opts]}) do
    opts = eval_literal(opts)
    into = opts |> Keyword.fetch!(:into) |> Enum.map(&to_path/1)
    {:split, to_path(source), Keyword.fetch!(opts, :by), into}
  end

  defp map_operation(other) do
    raise ArgumentError,
          "unsupported statement in a map block: #{Macro.to_string(other)}; " <>
            "expected rename/2, template/2, translate/3, or split/2"
  end

  defp to_path(value), do: value |> eval_literal() |> to_string()

  # Minimal literal evaluator for the handful of AST shapes the capture DSL accepts as
  # arguments: atoms, strings, numbers, booleans, lists, 2-tuples, escaped N-tuples, and maps.
  # Macro arguments always arrive as unexpanded AST; simple literals are "self-quoting" (an atom
  # or string literal's AST form equals its value), but 3+-element tuples and maps need unwrapping.
  @doc false
  @spec eval_literal(Macro.t()) :: term()
  def eval_literal({:%{}, _, pairs}) do
    pairs |> Enum.map(fn {k, v} -> {eval_literal(k), eval_literal(v)} end) |> Map.new()
  end

  def eval_literal({:{}, _, elements}) do
    elements |> Enum.map(&eval_literal/1) |> List.to_tuple()
  end

  def eval_literal({a, b}), do: {eval_literal(a), eval_literal(b)}
  def eval_literal(list) when is_list(list), do: Enum.map(list, &eval_literal/1)
  def eval_literal(other), do: other
end
