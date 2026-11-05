# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.GraphFixtures.Snapshot do
  @moduledoc false

  # Renders what a graph registers - the read model it is stored as and the projection that
  # fills it - as plain, JSON-comparable data with the wire names of the contract, so the
  # definition can be compared with the one the .NET client builds for the same graph.

  alias Chronicle.Graphs.DefinitionBuilder

  def of(graph, sink_type_id \\ "Neo4j") do
    read_model = DefinitionBuilder.read_model_definition(graph, sink_type_id)
    projection = DefinitionBuilder.projection_definition(graph)
    graph_definition = f(projection, :Graph)

    %{
      "readModel" => %{
        "type" => %{
          "identifier" => f(f(read_model, :Type), :Identifier),
          "generation" => f(f(read_model, :Type), :Generation)
        },
        "containerName" => f(read_model, :ContainerName),
        "displayName" => f(read_model, :DisplayName),
        "sinkTypeId" => f(f(read_model, :Sink), :TypeId),
        "observerIdentifier" => f(read_model, :ObserverIdentifier),
        "schema" => Jason.decode!(f(read_model, :Schema))
      },
      "projection" => %{
        "eventSequenceId" => f(projection, :EventSequenceId),
        "identifier" => f(projection, :Identifier),
        "readModel" => f(projection, :ReadModel),
        "isActive" => f(projection, :IsActive),
        "isRewindable" => f(projection, :IsRewindable),
        "initialModelState" => f(projection, :InitialModelState),
        "graph" => %{
          "nodes" =>
            Map.new(f(graph_definition, :Nodes), fn {label, node} ->
              {label, node_snapshot(node)}
            end),
          "edges" =>
            Map.new(f(graph_definition, :Edges), fn {type, edge} ->
              {type, edge_snapshot(edge)}
            end)
        }
      }
    }
  end

  defp f(struct, field), do: Map.fetch!(struct, field)

  defp node_snapshot(node) do
    %{
      "from" =>
        Map.new(f(node, :From), fn {event, from} ->
          {event,
           %{
             "key" => f(from, :Key),
             "properties" => f(from, :Properties),
             "updateOnly" => f(from, :UpdateOnly)
           }}
        end),
      "removedWith" =>
        Map.new(f(node, :RemovedWith), fn {event, removal} ->
          {event, %{"key" => f(removal, :Key), "detach" => f(removal, :Detach)}}
        end)
    }
  end

  defp edge_snapshot(edge) do
    %{
      "from" =>
        Map.new(f(edge, :From), fn {event, from} ->
          {event,
           %{
             "sourceKey" => f(from, :SourceKey),
             "targetKey" => f(from, :TargetKey),
             "identity" => f(from, :Identity),
             "properties" => f(from, :Properties)
           }}
        end),
      "removedWith" =>
        Map.new(f(edge, :RemovedWith), fn {event, removal} ->
          {event,
           %{
             "sourceKey" => f(removal, :SourceKey),
             "targetKey" => f(removal, :TargetKey),
             "identity" => f(removal, :Identity)
           }}
        end)
    }
  end
end
