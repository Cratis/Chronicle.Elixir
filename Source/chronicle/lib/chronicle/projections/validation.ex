# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.Validation do
  @moduledoc false

  # Compile-time validation shared by `Chronicle.ReadModels.ReadModel`,
  # `Chronicle.Projections.Projection` and `Chronicle.Projections.Children`. Every function here
  # runs while the declaring module is being compiled (inside a macro, before `quote`/`unquote`
  # produce code), so a mistake is a `CompileError` at `mix compile` time rather than a surprise
  # at registration. Callers pass plain strings/atoms, never unevaluated AST, so these functions
  # never need to guess whether a value is literal.

  @doc """
  Raises a `CompileError` naming `module` and the missing option, unless `opts` has `:identified_by`.
  """
  @spec require_identified_by!(atom(), Keyword.t(), module(), Macro.Env.t()) :: :ok
  def require_identified_by!(name, opts, module, env) do
    unless Keyword.has_key?(opts, :identified_by) do
      compile_error!(
        env,
        "children #{inspect(name)} on #{inspect(module)} requires :identified_by " <>
          "(the property of a child that identifies it)"
      )
    end

    :ok
  end

  @doc """
  Raises a `CompileError` naming `module` and the event, unless `opts` has `:on`. Used for a root
  `join/2` — a join inside a `children` block defaults `:on` instead of requiring it.
  """
  @spec require_on!(String.t(), Keyword.t(), module(), Macro.Env.t()) :: :ok
  def require_on!(event_label, opts, module, env) do
    unless Keyword.has_key?(opts, :on) do
      compile_error!(
        env,
        "Missing the on property expression for model of type '#{inspect(module)}' " <>
          "when joining with event of type '#{event_label}'"
      )
    end

    :ok
  end

  @doc """
  Resolves the `:on` property for a join inside a `children` block: defaults to `identified_by`
  when omitted, and warns (never raises — this stays additive) when an explicit `:on` disagrees
  with `identified_by`, since the kernel always joins a child by its identifying property.
  """
  @spec resolve_child_join_on(Keyword.t(), term(), module(), String.t()) :: String.t()
  def resolve_child_join_on(opts, identified_by, module, event_label) do
    identified_by_s = to_string(identified_by)

    case Keyword.fetch(opts, :on) do
      :error ->
        identified_by_s

      {:ok, on} ->
        on_s = to_string(on)

        if on_s != identified_by_s do
          IO.warn(
            "join #{event_label} inside children on #{inspect(module)} sets :on to " <>
              "#{inspect(on_s)}, which differs from :identified_by (#{inspect(identified_by_s)}). " <>
              "A child join always matches on the child's identifying property; :on is ignored here."
          )
        end

        on_s
    end
  end

  @doc """
  Raises a `CompileError` naming `module` and the duplicate target, when the same read-model
  property is assigned more than once by the combined `:set`, `:add`, `:subtract`, `:count`,
  `:increment`, `:decrement` and `:clear` options of a single event mapping. Mirrors the .NET
  client's `DuplicatePropertyInProjection`.
  """
  @spec reject_duplicate_properties!(String.t(), Keyword.t(), module(), Macro.Env.t()) :: :ok
  def reject_duplicate_properties!(event_label, opts, module, env) do
    targets =
      [
        opts |> Keyword.get(:set, []) |> Keyword.keys(),
        opts |> Keyword.get(:add, []) |> Keyword.keys(),
        opts |> Keyword.get(:subtract, []) |> Keyword.keys(),
        opts |> Keyword.get(:increment, []) |> Keyword.keys(),
        opts |> Keyword.get(:decrement, []) |> Keyword.keys(),
        opts |> Keyword.get(:clear, []) |> List.wrap(),
        opts |> Keyword.get(:count) |> List.wrap()
      ]
      |> List.flatten()

    case targets -- Enum.uniq(targets) do
      [] ->
        :ok

      duplicates ->
        [duplicate | _] = Enum.uniq(duplicates)

        compile_error!(
          env,
          "Property '#{duplicate}' has already been defined in the projection definition for " <>
            "#{inspect(module)} from event #{event_label}. Each property can only be specified once."
        )
    end
  end

  @doc """
  Returns the unique set of read-model property targets a `set`/`add`/`subtract`/`increment`/
  `decrement`/`clear`/`count` combination assigns, for struct-field validation.
  """
  @spec property_targets(Keyword.t()) :: [atom()]
  def property_targets(opts) do
    [
      opts |> Keyword.get(:set, []) |> Keyword.keys(),
      opts |> Keyword.get(:add, []) |> Keyword.keys(),
      opts |> Keyword.get(:subtract, []) |> Keyword.keys(),
      opts |> Keyword.get(:increment, []) |> Keyword.keys(),
      opts |> Keyword.get(:decrement, []) |> Keyword.keys(),
      opts |> Keyword.get(:clear, []) |> List.wrap(),
      opts |> Keyword.get(:count) |> List.wrap()
    ]
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Raises a `CompileError` naming `module` and `field`, unless `field` is one of `struct_fields`.
  Used for a property target or a `children` collection name that must be a real struct field.
  """
  @spec require_struct_field!(atom(), [atom()], module(), Macro.Env.t(), String.t()) :: :ok
  def require_struct_field!(field, struct_fields, module, env, what) do
    unless field in struct_fields do
      compile_error!(
        env,
        "#{what} #{inspect(field)} on #{inspect(module)} is not a field of its struct"
      )
    end

    :ok
  end

  @doc false
  def compile_error!(env, description) do
    raise CompileError, file: env.file, line: env.line, description: description
  end
end
