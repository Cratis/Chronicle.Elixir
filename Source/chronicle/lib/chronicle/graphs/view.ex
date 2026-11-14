# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.View do
  @moduledoc """
  Declares a **graph view**: a read model over an existing property graph.

  A view is anchored at one node of the graph, its **root**. Every member of a view is one of:

    * `property/2` - a property of the root node.
    * `relation/3` - follows one declared edge type in one direction to another view, and holds
      one value (`cardinality: :one`) or a list (`cardinality: :many`).
    * `edge_property/2` - a property of the edge that was followed to reach the view. Only valid
      in a view that is the target of a relation.

  Elixir structs carry no field types, so a view is declared with this macro DSL, in the style of
  `Chronicle.Graphs.Node` and `Chronicle.Graphs.Edge`, instead of with a typed struct:

      defmodule MyApp.Views.GroupMembership do
        use Chronicle.Graphs.View, root: MyApp.Graphs.Group

        property :id, source: :group_id
        property :name
        edge_property :since
      end

      defmodule MyApp.Views.PersonWithGroups do
        use Chronicle.Graphs.View, root: MyApp.Graphs.Person

        property :id, source: :person_id
        property :name
        relation :groups, MyApp.Graphs.MemberOf, view: MyApp.Views.GroupMembership, cardinality: :many
      end

  A view is not valid on its own. It is declared in the graph with `Chronicle.Graphs.Graph.view/1`,
  which is where it is checked against the nodes and edges of that graph:

      defmodule MyApp.Graphs.Organization do
        use Chronicle.Graphs.Graph, id: "Organization"
        # nodes and edges ...

        view MyApp.Views.PersonWithGroups
        view MyApp.Views.GroupMembership
      end

  The view declares what a read would return; it does not read. This client has no read side for
  graphs yet, so a view is validated and emitted as a `GraphViewDefinition`, see
  `Chronicle.Graphs.ViewDefinition`.

  ## Options of `use`

    * `:root` - the node module the view is anchored at. Required.
    * `:name` - the name of the view. Defaults to the last segment of the module name, and must be
      unique in a graph.

  ## Members

  The name of a member is the `camelCase` of its atom, as graph property names are. A `property`
  or an `edge_property` is matched to a property of the node or the edge by name, ignoring case,
  or by `source:`, which names the property explicitly.

  `relation/3` takes the edge module (or its type string, `"MEMBER_OF"`) and these options:

    * `:view` - the view module at the far end. Required.
    * `:cardinality` - `:many` or `:one`. Required; with `:one` an absent relation is `nil`.
    * `:direction` - `:outgoing` or `:incoming`. Derived from the root for an edge between two
      different nodes. A self edge (source and target are the same node) needs it.

  Members keep their declaration order.

  ## Compile-time errors

  A view that cannot work does not compile. The graph raises a `CompileError` pointing at the
  member, and the description starts with one of these reasons followed by a colon, for example
  `"UnknownEdge: ..."`:

    * `ViewRootNotANode` - the root is not a node declared in the graph
    * `ViewIsAlsoSchema` - a view module is also a node or an edge
    * `DuplicateViewName` - two views of a graph have the same name
    * `UnknownNodeProperty` - a `property` names a property the root node does not declare
    * `UnknownEdge` - a relation names an edge type the graph does not declare
    * `UnknownEdgeProperty` - an `edge_property` names a property the edge does not declare
    * `EdgeNotIncidentOnRoot` - the edge neither starts nor ends at the root (or does not do so in
      the given direction)
    * `AmbiguousDirection` - a relation follows a self edge without a `direction:`
    * `TargetLabelMismatch` - the target view is rooted at another node than the edge's far end
    * `RelationTargetNotAView` - the target of a relation is not a view declared in the graph
    * `RecursiveView` - a view contains itself, directly or through other views
    * `EdgePropertyViewNotUsedAsTarget` - a view with edge properties is no relation's target
    * `EdgePropertyViewSharedAcrossEdges` - a view with edge properties is the target of relations
      of more than one edge type

  The options and names of a member are checked where the view is declared: an unknown option, a
  missing `:view` or `:cardinality`, or a member name declared twice raises a `CompileError` too.

  ## Introspection

      MyApp.Views.PersonWithGroups.__chronicle_view__(:name)
      #=> "PersonWithGroups"
  """

  @view_opts [:root, :name]
  @property_opts [:source]
  @relation_opts [:view, :cardinality, :direction]

  @doc false
  defmacro __using__(opts) do
    line = __CALLER__.line

    quote do
      Module.register_attribute(__MODULE__, :chronicle_view_members, [])
      @chronicle_view_members []
      @chronicle_view_opts unquote(opts)
      @chronicle_view_file __ENV__.file
      @chronicle_view_line unquote(line)

      import Chronicle.Graphs.View,
        only: [property: 1, property: 2, edge_property: 1, edge_property: 2, relation: 3]

      @before_compile Chronicle.Graphs.View
    end
  end

  @doc """
  Adds a property of the root node to the view.

  The member is named by `name`; `source:` names the node property when it differs.
  """
  defmacro property(name, opts \\ []) do
    add(:property, name, nil, opts, __CALLER__.line)
  end

  @doc """
  Adds a property of the edge that was followed to the view.

  Only valid in a view that is the target of a relation. `source:` names the edge property when
  it differs from the member name.
  """
  defmacro edge_property(name, opts \\ []) do
    add(:edge_property, name, nil, opts, __CALLER__.line)
  end

  @doc """
  Adds a relation to another view, following `edge` from the root.

  `edge` is the edge module or its type string. Options: `view:`, `cardinality:` and
  `direction:`, see the module documentation.
  """
  defmacro relation(name, edge, opts) do
    add(:relation, name, edge, opts, __CALLER__.line)
  end

  defp add(kind, name, edge, opts, line) do
    quote do
      Chronicle.Graphs.View.__add__(
        __MODULE__,
        unquote(kind),
        unquote(name),
        unquote(edge),
        unquote(opts),
        unquote(line)
      )
    end
  end

  @doc false
  def __add__(module, kind, name, edge, opts, line) do
    file = Module.get_attribute(module, :chronicle_view_file)
    members = Module.get_attribute(module, :chronicle_view_members)

    unless is_atom(name) and not is_nil(name) and not is_boolean(name),
      do: fail!(file, line, "the name of a member must be an atom, got #{inspect(name)}")

    unless Keyword.keyword?(opts),
      do: fail!(file, line, "the options of #{inspect(name)} must be a keyword list")

    member = member(kind, name, edge, opts, file, line)

    if Enum.any?(members, &(String.downcase(&1.name) == String.downcase(member.name))) do
      fail!(file, line, "member #{inspect(name)} is declared more than once in the view")
    end

    Module.put_attribute(module, :chronicle_view_members, members ++ [member])
  end

  defp member(kind, name, _edge, opts, file, line) when kind in [:property, :edge_property] do
    reject_unknown_opts!(file, line, opts, @property_opts, "#{kind} #{inspect(name)}")

    %{
      kind: kind,
      name: property_name(name),
      source: source(file, line, Keyword.get(opts, :source, name)),
      line: line
    }
  end

  defp member(:relation, name, edge, opts, file, line) do
    reject_unknown_opts!(file, line, opts, @relation_opts, "relation #{inspect(name)}")

    unless (is_atom(edge) and not is_nil(edge)) or is_binary(edge) do
      fail!(
        file,
        line,
        "relation #{inspect(name)} must name an edge module or an edge type string"
      )
    end

    view = Keyword.get(opts, :view)

    unless is_atom(view) and not is_nil(view),
      do: fail!(file, line, "relation #{inspect(name)} needs `view:`, the view it leads to")

    cardinality = Keyword.get(opts, :cardinality)

    unless cardinality in [:many, :one] do
      fail!(
        file,
        line,
        "relation #{inspect(name)} needs `cardinality:`, :many or :one, got #{inspect(cardinality)}"
      )
    end

    direction = Keyword.get(opts, :direction)

    unless direction in [nil, :outgoing, :incoming] do
      fail!(
        file,
        line,
        "direction of relation #{inspect(name)} must be :outgoing or :incoming, " <>
          "got #{inspect(direction)}"
      )
    end

    %{
      kind: :relation,
      name: property_name(name),
      edge: edge,
      direction: direction,
      cardinality: cardinality,
      view: view,
      line: line
    }
  end

  defp source(_file, _line, source) when is_binary(source), do: source

  defp source(file, line, source) do
    if is_atom(source) and not is_nil(source),
      do: property_name(source),
      else: fail!(file, line, "source must be an atom or a string, got #{inspect(source)}")
  end

  defp reject_unknown_opts!(file, line, opts, allowed, what) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      unknown ->
        fail!(
          file,
          line,
          "#{what} does not support #{Enum.map_join(Enum.uniq(unknown), ", ", &inspect/1)}; " <>
            "supported options: #{Enum.map_join(allowed, ", ", &inspect/1)}"
        )
    end
  end

  defp property_name(field), do: Chronicle.Graphs.Compiler.property_name(field)

  defp fail!(file, line, message),
    do: raise(CompileError, file: file, line: line, description: message)

  @doc false
  defmacro __before_compile__(env) do
    file = Module.get_attribute(env.module, :chronicle_view_file)
    line = Module.get_attribute(env.module, :chronicle_view_line)
    opts = Module.get_attribute(env.module, :chronicle_view_opts)

    unless Keyword.keyword?(opts),
      do: fail!(file, line, "the options of a view must be a keyword list")

    reject_unknown_opts!(file, line, opts, @view_opts, "a view")

    root = Keyword.get(opts, :root)

    unless is_atom(root) and not is_nil(root) do
      fail!(
        file,
        line,
        "a view needs a root: name the node it is anchored at, " <>
          "for example `use Chronicle.Graphs.View, root: MyApp.Graphs.Person`"
      )
    end

    name = Keyword.get(opts, :name, env.module |> Module.split() |> List.last())

    declaration = %{
      module: env.module,
      name: name,
      root: root,
      file: file,
      line: line,
      members: Module.get_attribute(env.module, :chronicle_view_members)
    }

    quote do
      @doc false
      def __chronicle_view__(:name), do: unquote(name)

      @doc false
      def __chronicle_view__(:declaration), do: unquote(Macro.escape(declaration))
    end
  end
end
