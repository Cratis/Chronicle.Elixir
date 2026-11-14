# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.ViewCompiler do
  @moduledoc false

  # Validates the views a `Chronicle.Graphs.Graph` module declares with `view/1` against the nodes
  # and edges of the same graph, and normalizes them into the description the view definition is
  # written from. It runs at compile time, so a graph with a view that cannot work does not compile.
  #
  # Every rejection is a `CompileError` whose description starts with the stable reason code and a
  # colon, for example `"UnknownEdge: ..."`. The thirteen reasons are the ones of the shared graph
  # views specification.

  alias Chronicle.Graphs.Compiler

  @doc """
  Validates and normalizes the view declarations of the graph compiled in `env`.

  `declarations` are the `%{kind: :view, module: module, file: file, line: line}` entries the graph
  collected, `nodes` and `edges` the output of `Chronicle.Graphs.Compiler.compile!/2`.
  """
  @spec compile!(Macro.Env.t(), [map()], [map()], [map()]) :: [map()]
  def compile!(_env, [], _nodes, _edges), do: []

  def compile!(env, declarations, nodes, edges) do
    views = Enum.map(declarations, &load!/1)
    reject_duplicate_names!(env, views)
    views = Enum.map(views, &resolve_root!(&1, nodes))
    by_module = Map.new(views, &{&1.module, &1})

    resolved = Enum.map(views, &resolve_members!(&1, by_module, nodes, edges))
    reject_recursion!(resolved)
    resolved = verify_edge_property_views!(resolved, edges)

    Enum.map(resolved, &finish/1)
  end

  # --- loading ---------------------------------------------------------------------------

  defp load!(%{module: module, file: file, line: line, graph_line: graph_line}) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        unless function_exported?(module, :__chronicle_view__, 1) do
          raise CompileError,
            file: file,
            line: line,
            description:
              "#{inspect(module)} must `use Chronicle.Graphs.View` to be a view of a graph"
        end

        reject_schema!(module, file, line)
        Map.put(module.__chronicle_view__(:declaration), :graph_line, graph_line)

      {:error, reason} ->
        raise CompileError,
          file: file,
          line: line,
          description:
            "cannot use #{inspect(module)} as a view: it could not be compiled (#{reason})"
    end
  end

  defp reject_schema!(module, file, line) do
    if function_exported?(module, :__chronicle_graph_node__, 1) or
         function_exported?(module, :__chronicle_graph_edge__, 1) do
      fail!(
        file,
        line,
        "ViewIsAlsoSchema",
        "#{inspect(module)} is a view and also a node or an edge: a view type must not " <>
          "also be part of the graph schema"
      )
    end
  end

  defp reject_duplicate_names!(env, views) do
    views
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn
      {_name, [_single]} ->
        :ok

      {name, [_first, second | _]} ->
        fail!(
          env.file,
          second.graph_line,
          "DuplicateViewName",
          "view name #{inspect(name)} is declared more than once in the graph: " <>
            "name one of the views with `use Chronicle.Graphs.View, name: ...`"
        )
    end)
  end

  defp resolve_root!(view, nodes) do
    case Enum.find(nodes, &(&1.module == view.root)) do
      nil ->
        fail!(
          view.file,
          view.line,
          "ViewRootNotANode",
          "view #{view.name} has root #{inspect(view.root)}, which is not declared as a node " <>
            "of the graph: declare it with `node #{inspect(view.root)}, key: ...`"
        )

      node ->
        Map.merge(view, %{root_label: node.label, root_node: node})
    end
  end

  # --- members ---------------------------------------------------------------------------

  defp resolve_members!(view, by_module, nodes, edges) do
    members = Enum.map(view.members, &resolve_member!(&1, view, by_module, nodes, edges))
    %{view | members: members}
  end

  defp resolve_member!(%{kind: :property} = member, view, _by_module, _nodes, _edges) do
    source = canonical!(view.root_node.properties, member.source)

    unless source do
      fail!(
        view.file,
        member.line,
        "UnknownNodeProperty",
        "property #{inspect(member.name)} of view #{view.name} names #{inspect(member.source)}, " <>
          "which node #{view.root_label} does not declare: " <>
          "its properties are #{Enum.map_join(view.root_node.properties, ", ", &inspect/1)}"
      )
    end

    %{member | source: source}
  end

  defp resolve_member!(%{kind: :edge_property} = member, _view, _by_module, _nodes, _edges),
    do: member

  defp resolve_member!(%{kind: :relation} = member, view, by_module, _nodes, edges) do
    edge = find_edge!(member, view, edges)
    direction = direction!(member, view, edge)

    target =
      Map.get(by_module, member.view) ||
        fail!(
          view.file,
          member.line,
          "RelationTargetNotAView",
          "relation #{inspect(member.name)} of view #{view.name} targets #{inspect(member.view)}, " <>
            "which is not a view declared in the graph: declare it with `view #{inspect(member.view)}`"
        )

    far = if direction == :outgoing, do: edge.target, else: edge.source

    if target.root_label != far do
      fail!(
        view.file,
        member.line,
        "TargetLabelMismatch",
        "relation #{inspect(member.name)} of view #{view.name} follows #{edge.type} " <>
          "#{direction} to a #{far}, but its target view #{target.name} is rooted at " <>
          "#{target.root_label}"
      )
    end

    %{member | direction: direction, edge: edge.type, view: target.name}
    |> Map.merge(%{target_module: target.module, edge_module: edge.module})
  end

  defp find_edge!(member, view, edges) do
    found =
      case member.edge do
        type when is_binary(type) -> Enum.find(edges, &(&1.type == type))
        module -> Enum.find(edges, &(&1.module == module))
      end

    found ||
      fail!(
        view.file,
        member.line,
        "UnknownEdge",
        "relation #{inspect(member.name)} of view #{view.name} names edge " <>
          "#{inspect(member.edge)}, which the graph does not declare"
      )
  end

  # The direction of a non-self edge is derived from the root label. A self edge has no derivable
  # direction and needs the explicit one. An explicit direction that the root label contradicts
  # means the edge does not leave (or enter) the root in that direction, which is the same
  # rejection as an edge that is not incident on the root.
  defp direction!(member, view, edge) do
    root = view.root_label
    explicit = member.direction

    cond do
      edge.source == root and edge.target == root ->
        explicit ||
          fail!(
            view.file,
            member.line,
            "AmbiguousDirection",
            "relation #{inspect(member.name)} of view #{view.name} follows #{edge.type}, a self " <>
              "edge of #{root}: give the direction, `direction: :outgoing` or `direction: :incoming`"
          )

      edge.source == root and explicit in [nil, :outgoing] ->
        :outgoing

      edge.target == root and explicit in [nil, :incoming] ->
        :incoming

      true ->
        fail!(
          view.file,
          member.line,
          "EdgeNotIncidentOnRoot",
          "relation #{inspect(member.name)} of view #{view.name} follows #{edge.type} " <>
            "(#{edge.source} to #{edge.target})#{if explicit, do: " #{explicit}"}, " <>
            "which is not incident on the root #{root}"
        )
    end
  end

  # --- recursion -------------------------------------------------------------------------

  defp reject_recursion!(views) do
    targets =
      Map.new(views, fn view ->
        {view.module, for(%{kind: :relation} = member <- view.members, do: member)}
      end)

    by_module = Map.new(views, &{&1.module, &1})
    Enum.each(views, &walk!(&1.module, [], targets, by_module))
  end

  defp walk!(module, path, targets, by_module) do
    Enum.each(Map.fetch!(targets, module), fn member ->
      cond do
        member.target_module in [module | path] ->
          view = Map.fetch!(by_module, module)

          fail!(
            view.file,
            member.line,
            "RecursiveView",
            "view #{view.name} contains itself through relation #{inspect(member.name)} to " <>
              "#{member.view}: the nesting of a view is finite"
          )

        true ->
          walk!(member.target_module, [module | path], targets, by_module)
      end
    end)
  end

  # --- edge properties -------------------------------------------------------------------

  defp verify_edge_property_views!(views, edges) do
    uses =
      for view <- views,
          %{kind: :relation} = member <- view.members,
          do: {member.target_module, member.edge}

    Enum.map(views, fn view ->
      case Enum.filter(view.members, &(&1.kind == :edge_property)) do
        [] -> view
        _properties -> verify_edge_properties!(view, uses, edges)
      end
    end)
  end

  defp verify_edge_properties!(view, uses, edges) do
    followed = for {module, edge} <- uses, module == view.module, uniq: true, do: edge

    case followed do
      [] ->
        fail!(
          view.file,
          view.line,
          "EdgePropertyViewNotUsedAsTarget",
          "view #{view.name} has edge properties but no relation targets it: an edge property " <>
            "is a property of the edge that was followed"
        )

      [edge_type] ->
        edge = Enum.find(edges, &(&1.type == edge_type))

        members =
          Enum.map(view.members, fn
            %{kind: :edge_property} = member ->
              source = canonical!(edge.properties, member.source)

              unless source do
                fail!(
                  view.file,
                  member.line,
                  "UnknownEdgeProperty",
                  "edge property #{inspect(member.name)} of view #{view.name} names " <>
                    "#{inspect(member.source)}, which edge #{edge.type} does not declare: " <>
                    "its properties are #{Enum.map_join(edge.properties, ", ", &inspect/1)}"
                )
              end

              %{member | source: source}

            member ->
              member
          end)

        %{view | members: members}

      several ->
        fail!(
          view.file,
          view.line,
          "EdgePropertyViewSharedAcrossEdges",
          "view #{view.name} has edge properties and is the target of relations of more than one " <>
            "edge type (#{Enum.join(several, ", ")}): give each edge its own view"
        )
    end
  end

  # --- output ----------------------------------------------------------------------------

  defp finish(view) do
    %{
      module: view.module,
      name: view.name,
      root: view.root_label,
      members: Enum.map(view.members, &finish_member/1)
    }
  end

  defp finish_member(%{kind: :relation} = member) do
    %{
      name: member.name,
      kind: :relation,
      edge: member.edge,
      direction: member.direction,
      cardinality: member.cardinality,
      view: member.view
    }
  end

  defp finish_member(member), do: Map.take(member, [:name, :kind, :source])

  # The declared spelling of the property a member names. A member matches a property by name,
  # ignoring case, after both have been through the client's naming policy.
  defp canonical!(properties, source) do
    wanted = String.downcase(source)
    Enum.find(properties, &(String.downcase(&1) == wanted))
  end

  defp fail!(file, line, reason, message) do
    raise CompileError, file: file, line: line, description: "#{reason}: #{message}"
  end

  @doc false
  def property_name(field), do: Compiler.property_name(field)
end
