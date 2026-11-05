# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.DefinitionBuilder do
  @moduledoc false

  # Builds what the registration coordinator sends for a graph: the read model the graph is
  # stored as, and the projection that fills it. The shape follows the .NET client's
  # GraphDefinitionBuilder, so the same graph declared in either client registers the same
  # definition.

  alias Bcl.Guid, as: BclGuid
  alias Chronicle.Graphs.SchemaWriter

  alias Cratis.Chronicle.Contracts.Projections.{
    FromEveryDefinition,
    GraphEdgeFromDefinition,
    GraphEdgeProjectionDefinition,
    GraphEdgeRemovedWithDefinition,
    GraphNodeFromDefinition,
    GraphNodeProjectionDefinition,
    GraphNodeRemovedWithDefinition,
    GraphProjectionDefinition,
    ProjectionDefinition
  }

  alias Cratis.Chronicle.Contracts.ReadModels.{ReadModelDefinition, ReadModelType, SinkDefinition}

  @doc "Builds the read model definition of the graph, stored by the sink of the given type."
  @spec read_model_definition(module(), String.t()) :: struct()
  def read_model_definition(graph, sink_type_id) do
    id = graph.__chronicle_graph__(:id)

    struct(ReadModelDefinition,
      Type: struct(ReadModelType, Identifier: id, Generation: 1),
      ContainerName: id,
      DisplayName: id,
      Sink: struct(SinkDefinition, ConfigurationId: struct(BclGuid), TypeId: sink_type_id),
      Schema: SchemaWriter.write(graph),
      ObserverType: 2,
      ObserverIdentifier: id,
      Owner: 2,
      Source: 1
    )
  end

  @doc "Builds the projection definition that fills the graph."
  @spec projection_definition(module()) :: struct()
  def projection_definition(graph) do
    id = graph.__chronicle_graph__(:id)

    nodes = Map.new(graph.__chronicle_graph__(:nodes), &{&1.label, node_definition(&1)})
    edges = Map.new(graph.__chronicle_graph__(:edges), &{&1.type, edge_definition(&1)})

    struct(ProjectionDefinition,
      EventSequenceId: "event-log",
      Identifier: id,
      ReadModel: id,
      IsActive: true,
      IsRewindable: true,
      InitialModelState: "{}",
      All: struct(FromEveryDefinition),
      Graph: struct(GraphProjectionDefinition, Nodes: nodes, Edges: edges)
    )
  end

  defp node_definition(node) do
    struct(GraphNodeProjectionDefinition,
      From:
        Map.new(node.from, fn from ->
          {event_type(from.event),
           struct(GraphNodeFromDefinition,
             Key: from.key,
             Properties: from.properties,
             UpdateOnly: from.update_only
           )}
        end),
      RemovedWith:
        Map.new(node.removed_with, fn removal ->
          {event_type(removal.event),
           struct(GraphNodeRemovedWithDefinition, Key: removal.key, Detach: removal.detach)}
        end)
    )
  end

  defp edge_definition(edge) do
    struct(GraphEdgeProjectionDefinition,
      From:
        Map.new(edge.from, fn from ->
          {event_type(from.event),
           struct(GraphEdgeFromDefinition,
             SourceKey: from.source_key,
             TargetKey: from.target_key,
             Identity: from.identity || "",
             Properties: from.properties
           )}
        end),
      RemovedWith:
        Map.new(edge.removed_with, fn removal ->
          {event_type(removal.event),
           struct(GraphEdgeRemovedWithDefinition,
             SourceKey: removal.source_key,
             TargetKey: removal.target_key,
             Identity: removal.identity || ""
           )}
        end)
    )
  end

  # The kernel keys a graph's event mappings by the string form of the event type: id+generation.
  defp event_type(event) do
    "#{event.__chronicle_event_type__(:id)}+#{event.__chronicle_event_type__(:generation)}"
  end
end
