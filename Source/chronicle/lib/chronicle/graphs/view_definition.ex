# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.ViewDefinition do
  @moduledoc """
  The `GraphViewDefinition` of a graph: its views, as plain data and as canonical JSON.

  The definition is a transport and conformance format shared by every Chronicle client, never
  authored by hand. It is built from the views a graph declares with
  `Chronicle.Graphs.Graph.view/1` and is not sent to the kernel: nothing about the wire changes.

      Chronicle.Graphs.ViewDefinition.build(MyApp.Graphs.Organization)
      #=> %{graph: "Organization", views: [%{name: "GroupMembership", root: "Group", members: [...]}]}

      Chronicle.Graphs.ViewDefinition.encode(MyApp.Graphs.Organization)
      #=> "{\\n  \\"graph\\": \\"Organization\\",\\n  \\"views\\": [..."

  A graph without views has an empty definition, `%{graph: id, views: []}`.

  ## Canonical form

  UTF-8, LF line ends, two-space indentation, one trailing newline. Views are sorted by name
  (ordinal), members keep their declaration order. A member is written on one line:

      { "name": "groups", "kind": "relation", "edge": "MEMBER_OF", "direction": "outgoing", "cardinality": "many", "view": "GroupMembership" }

  Because the encoder is written by hand, the property order and the layout never depend on a JSON
  library.

  ## Conformance form

  The shared conformance fixture also lists the schema (nodes and edges) the views are declared
  over. `encode/2` writes it between `graph` and `views` with `include_schema: true`; that form is
  what the conformance specs compare byte for byte. The default form leaves it out.
  """

  @type member :: %{required(atom()) => term()}
  @type view :: %{name: String.t(), root: String.t(), members: [member()]}
  @type t :: %{graph: String.t(), views: [view()]}

  @doc """
  Builds the definition of `graph`, a module that `use Chronicle.Graphs.Graph`.

  Views are sorted by name, ordinal. Directions and cardinalities are the strings of the format.
  """
  @spec build(module()) :: t()
  def build(graph) do
    views =
      graph.__chronicle_graph__(:views)
      |> Enum.map(&Map.delete(&1, :module))
      |> Enum.map(&stringify/1)
      |> Enum.sort_by(& &1.name)

    %{graph: graph.__chronicle_graph__(:id), views: views}
  end

  defp stringify(view) do
    %{view | members: Enum.map(view.members, &stringify_member/1)}
  end

  defp stringify_member(%{kind: kind} = member) do
    member = %{member | kind: kind_name(kind)}

    case member do
      %{direction: direction, cardinality: cardinality} ->
        %{member | direction: Atom.to_string(direction), cardinality: Atom.to_string(cardinality)}

      _ ->
        member
    end
  end

  defp kind_name(:edge_property), do: "edgeProperty"
  defp kind_name(kind), do: Atom.to_string(kind)

  @doc """
  Serializes the definition of `graph` canonically.

  Options:

    * `:include_schema` - also write the nodes and edges of the graph, as the conformance fixture
      does. Defaults to `false`.
  """
  @spec encode(module(), keyword()) :: String.t()
  def encode(graph, opts \\ []) do
    definition = build(graph)

    schema =
      if Keyword.get(opts, :include_schema, false),
        do: ["  \"schema\": ", schema(graph), ",\n"],
        else: []

    IO.iodata_to_binary([
      "{\n  \"graph\": ",
      string(definition.graph),
      ",\n",
      schema,
      "  \"views\": ",
      views(definition.views),
      "\n}\n"
    ])
  end

  defp views([]), do: "[]"

  defp views(views) do
    ["[\n", Enum.intersperse(Enum.map(views, &view/1), ",\n"), "\n  ]"]
  end

  defp view(view) do
    [
      "    {\n      \"name\": ",
      string(view.name),
      ",\n      \"root\": ",
      string(view.root),
      ",\n      \"members\": ",
      members(view.members),
      "\n    }"
    ]
  end

  defp members([]), do: "[]"

  defp members(members) do
    ["[\n", Enum.intersperse(Enum.map(members, &["        ", member(&1)]), ",\n"), "\n      ]"]
  end

  defp member(%{kind: "relation"} = member),
    do:
      object([
        {"name", member.name},
        {"kind", member.kind},
        {"edge", member.edge},
        {"direction", member.direction},
        {"cardinality", member.cardinality},
        {"view", member.view}
      ])

  defp member(member),
    do: object([{"name", member.name}, {"kind", member.kind}, {"source", member.source}])

  defp object(pairs),
    do: [
      "{ ",
      Enum.intersperse(for({k, v} <- pairs, do: [string(k), ": ", string(v)]), ", "),
      " }"
    ]

  defp schema(graph) do
    nodes =
      for node <- graph.__chronicle_graph__(:nodes) do
        object_of([
          {"label", string(node.label)},
          {"key", string(node.key)},
          {"properties", list(node.properties)}
        ])
      end

    edges =
      for edge <- graph.__chronicle_graph__(:edges) do
        identity = if edge.identity, do: [{"identifiedBy", string(edge.identity)}], else: []

        object_of(
          [
            {"type", string(edge.type)},
            {"source", string(edge.source)},
            {"target", string(edge.target)}
          ] ++ identity ++ [{"properties", list(edge.properties)}]
        )
      end

    [
      "{\n    \"nodes\": ",
      schema_list(nodes),
      ",\n    \"edges\": ",
      schema_list(edges),
      "\n  }"
    ]
  end

  defp schema_list([]), do: "[]"

  defp schema_list(items),
    do: ["[\n", Enum.intersperse(Enum.map(items, &["      ", &1]), ",\n"), "\n    ]"]

  defp object_of(pairs),
    do: ["{ ", Enum.intersperse(for({k, v} <- pairs, do: [string(k), ": ", v]), ", "), " }"]

  defp list([]), do: "[]"
  defp list(values), do: ["[ ", Enum.intersperse(Enum.map(values, &string/1), ", "), " ]"]

  defp string(value), do: Jason.encode!(value)
end
