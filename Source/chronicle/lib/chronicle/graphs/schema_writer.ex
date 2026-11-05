# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.SchemaWriter do
  @moduledoc false

  # Writes the read model schema a graph is registered with. The graph target definition is
  # carried as `x-graph-*` annotations inside an ordinary JSON schema, exactly as the .NET
  # client's GraphSchemaWriter writes it and the kernel's GraphDefinition.FromSchema reads it:
  # the root is marked `x-graph`, every node and edge is a property of the root named after its
  # label or type, and an element's own properties are the properties of its struct.

  alias Chronicle.Graphs.Compiler
  alias Chronicle.Schemas.JsonSchemaGenerator

  @doc "Writes the schema of the graph module as a JSON string."
  @spec write(module()) :: String.t()
  def write(graph) do
    nodes = for node <- graph.__chronicle_graph__(:nodes), do: {node.label, node_schema(node)}
    edges = for edge <- graph.__chronicle_graph__(:edges), do: {edge.type, edge_schema(edge)}

    ordered([
      {"type", "object"},
      {"title", graph.__chronicle_graph__(:id)},
      {"x-graph", true},
      {"properties", ordered(nodes ++ edges)}
    ])
    |> Jason.encode!()
  end

  defp node_schema(node) do
    element(node.module)
    |> Kernel.++([{"x-graph-kind", "Node"}, {"x-graph-key", node.key}])
    |> ordered()
  end

  defp edge_schema(edge) do
    identity = if edge.identity, do: [{"x-graph-identity", edge.identity}], else: []

    (element(edge.module) ++
       [
         {"x-graph-kind", "Edge"},
         {"x-graph-source", edge.source},
         {"x-graph-target", edge.target}
       ] ++ identity)
    |> ordered()
  end

  # The struct's fields in declaration order, each described by the schema the client uses for
  # every other struct-backed model, so a property has the same type here as it has anywhere.
  defp element(module) do
    schema = module |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

    properties =
      for %{field: field} <- Compiler.struct_fields(module) do
        name = Compiler.property_name(field)
        {name, schema |> get_in(["properties", name]) |> order_schema()}
      end

    [{"type", "object"}, {"properties", ordered(properties)}]
  end

  defp order_schema(%{"type" => type} = schema) do
    rest = schema |> Map.delete("type") |> Enum.sort() |> Enum.map(&order_value/1)
    ordered([{"type", type} | rest])
  end

  defp order_schema(schema), do: schema

  defp order_value({key, %{} = value}), do: {key, order_schema(value)}
  defp order_value(pair), do: pair

  defp ordered(pairs), do: Jason.OrderedObject.new(pairs)
end
