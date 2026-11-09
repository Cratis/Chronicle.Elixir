# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.Children.Ordering do
  @moduledoc false

  # Where a `children` collection places a new child. Mirrors the .NET client's
  # `IChildrenBuilder.Prepend()`, `OrderBy()` and `OrderByDescending()`:
  #
  #   children :items, identified_by: :id                          — append (the default)
  #   children :items, identified_by: :id, prepend: true            — newest first
  #   children :items, identified_by: :id, order_by: :position      — sorted ascending
  #   children :items, identified_by: :id, order_by: [desc: :total] — sorted descending
  #
  # Ordering only decides where a new child is inserted; it does not re-sort when a child changes.

  alias Chronicle.Projections.Validation
  alias Cratis.Chronicle.Contracts.Projections.ChildrenOrderingDefinition

  @typedoc "A non-default placement for new children."
  @type t :: :prepend | {:sorted, String.t(), :ascending | :descending}

  @doc false
  @spec options() :: [atom()]
  def options, do: [:prepend, :order_by]

  @doc """
  Raises a `CompileError` when the ordering options of `children name` are malformed or conflict.
  """
  @spec validate!(atom(), Keyword.t(), Macro.Env.t()) :: :ok
  def validate!(name, opts, env) do
    case ordering(opts) do
      {:ok, _ordering} -> :ok
      {:error, reason} -> Validation.compile_error!(env, "children #{inspect(name)}: #{reason}")
    end
  end

  @doc """
  Returns the placement `opts` declare, `nil` for the default of appending, or raises
  `ArgumentError` when the options are malformed or conflict.
  """
  @spec from_options(Keyword.t()) :: t() | nil
  def from_options(opts) do
    case ordering(opts) do
      {:ok, ordering} -> ordering
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Adds the `Ordering` of a `ChildrenDefinition` when `opts` declare one, and leaves the definition
  exactly as before when they do not.
  """
  @spec put_definition(struct(), Keyword.t()) :: struct()
  def put_definition(definition, opts) do
    case from_options(opts) do
      nil -> definition
      ordering -> %{definition | Ordering: struct!(ChildrenOrderingDefinition, fields(ordering))}
    end
  end

  @doc """
  Returns the `ChildrenOrderingDefinition` fields of `ordering`.
  """
  @spec fields(t()) :: keyword()
  def fields(:prepend), do: [Placement: :Prepend, SortBy: "", Direction: :Ascending]

  def fields({:sorted, sort_by, direction}),
    do: [Placement: :Sorted, SortBy: sort_by, Direction: direction_value(direction)]

  defp direction_value(:ascending), do: :Ascending
  defp direction_value(:descending), do: :Descending

  defp ordering(opts) do
    case {Keyword.get(opts, :prepend, false), Keyword.fetch(opts, :order_by)} do
      {false, :error} -> {:ok, nil}
      {true, :error} -> {:ok, :prepend}
      {false, {:ok, order_by}} -> sorted(order_by)
      {true, {:ok, _}} -> {:error, "use either prepend: true or order_by, not both"}
      {other, _} -> {:error, "prepend must be true or false, got #{Macro.to_string(other)}"}
    end
  end

  defp sorted(field) when is_atom(field) and not is_nil(field) and not is_boolean(field),
    do: {:ok, {:sorted, Atom.to_string(field), :ascending}}

  defp sorted(asc: field) when is_atom(field) and not is_nil(field),
    do: {:ok, {:sorted, Atom.to_string(field), :ascending}}

  defp sorted(desc: field) when is_atom(field) and not is_nil(field),
    do: {:ok, {:sorted, Atom.to_string(field), :descending}}

  defp sorted(other) do
    {:error,
     "order_by must be a child property such as :position, [asc: :position] or " <>
       "[desc: :position], got #{Macro.to_string(other)}"}
  end
end
