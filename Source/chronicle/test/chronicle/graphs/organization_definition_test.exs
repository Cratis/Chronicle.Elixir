# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.OrganizationDefinitionTest do
  use ExUnit.Case, async: true

  alias Chronicle.GraphFixtures.{Organization, Snapshot}
  alias Chronicle.Graphs.SchemaWriter
  alias Chronicle.Sinks.WellKnownSinkTypes

  # The fixture is the definition the .NET client builds for the same Organization graph (see
  # Source/Clients/DotNET.Specs/Projections/Graphs/for_GraphDefinitionBuilder), written out with
  # the wire names of the contract: the graph target as `x-graph-*` annotations in the read model
  # schema, and the graph projection keyed by `<event type id>+<generation>`. Properties are
  # strings and counters here; the numeric schema type is the one the Elixir client gives every
  # number (see Chronicle.Schemas.JsonSchemaGenerator), where .NET writes integer/int32.
  @fixture "test/fixtures/graphs/organization.json"
           |> Path.expand(File.cwd!())
           |> File.read!()
           |> Jason.decode!()

  test "produces the definition the .NET client produces for the same graph" do
    assert Snapshot.of(Organization) == @fixture
  end

  test "registers the graph as a read model stored by the sink it is given" do
    assert Snapshot.of(Organization, WellKnownSinkTypes.in_memory_graph())["readModel"][
             "sinkTypeId"
           ] == "InMemoryGraph"
  end

  test "names the graph, its read model and its projection after the graph id" do
    assert Organization.__chronicle_graph__(:id) == "Organization"
    assert @fixture["projection"]["identifier"] == "Organization"
    assert @fixture["projection"]["readModel"] == "Organization"
  end

  test "writes the schema in the order the .NET client writes it" do
    schema = SchemaWriter.write(Organization)

    assert schema ==
             ~s({"type":"object","title":"Organization","x-graph":true,"properties":{) <>
               ~s("Person":{"type":"object","properties":{"personId":{"type":"string"},"name":{"type":"string"}},"x-graph-kind":"Node","x-graph-key":"personId"},) <>
               ~s("Group":{"type":"object","properties":{"groupId":{"type":"string"},"name":{"type":"string"},"memberCount":{"type":"number"}},"x-graph-kind":"Node","x-graph-key":"groupId"},) <>
               ~s("Place":{"type":"object","properties":{"placeId":{"type":"string"}},"x-graph-kind":"Node","x-graph-key":"placeId"},) <>
               ~s("MEMBER_OF":{"type":"object","properties":{"since":{"type":"string"}},"x-graph-kind":"Edge","x-graph-source":"Person","x-graph-target":"Group"},) <>
               ~s("VISITED":{"type":"object","properties":{"visitId":{"type":"string"},"times":{"type":"number"}},"x-graph-kind":"Edge","x-graph-source":"Person","x-graph-target":"Place","x-graph-identity":"visitId"}}})
  end

  test "lists every event type the graph handles, once" do
    assert Organization.__chronicle_graph__(:events) |> Enum.sort() ==
             Enum.sort([
               Chronicle.GraphFixtures.PersonRegistered,
               Chronicle.GraphFixtures.PersonRemoved,
               Chronicle.GraphFixtures.GroupCreated,
               Chronicle.GraphFixtures.MemberAdded,
               Chronicle.GraphFixtures.MemberRemoved,
               Chronicle.GraphFixtures.PlaceVisited
             ])
  end

  test "is discovered as a graph artifact" do
    assert Organization in Chronicle.Artifacts.discover_loaded().graphs
  end

  test "the graph sinks resolve from atoms" do
    assert WellKnownSinkTypes.resolve(:neo4j) == "Neo4j"
    assert WellKnownSinkTypes.resolve(:in_memory_graph) == "InMemoryGraph"
  end
end
