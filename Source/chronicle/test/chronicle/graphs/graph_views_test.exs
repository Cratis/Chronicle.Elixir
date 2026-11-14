# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.GraphViewsTest do
  use ExUnit.Case, async: true

  alias Chronicle.GraphFixtures.Organization, as: ProjectedOrganization
  alias Chronicle.GraphViewFixtures.Organization
  alias Chronicle.Graphs.ViewDefinition

  @fixture_path Path.expand("../../fixtures/graphs/graph-views-organization.json", __DIR__)
  @fixture File.read!(@fixture_path)

  test "emits the shared conformance fixture byte for byte" do
    assert ViewDefinition.encode(Organization, include_schema: true) == @fixture
  end

  test "emits the definition without the schema in the same canonical layout" do
    expected =
      @fixture
      |> Jason.decode!()
      |> Map.delete("schema")

    emitted = ViewDefinition.encode(Organization)

    assert Jason.decode!(emitted) == expected
    refute emitted =~ "schema"

    assert String.starts_with?(
             emitted,
             "{\n  \"graph\": \"Organization\",\n  \"views\": [\n    {\n"
           )

    assert String.ends_with?(emitted, "  ]\n}\n")
  end

  test "sorts views by name although they are declared in another order" do
    names = Organization |> ViewDefinition.build() |> Map.fetch!(:views) |> Enum.map(& &1.name)

    assert names == Enum.sort(names)
    assert length(names) == 8
  end

  test "keeps the declaration order of members" do
    view = ViewDefinition.build(Organization).views |> Enum.find(&(&1.name == "RoleAssignment"))

    assert Enum.map(view.members, & &1.name) == ["id", "assignmentId", "role"]
  end

  test "lists the views through the introspection function" do
    assert Organization.__chronicle_graph__(:views) |> Enum.map(& &1.name) |> Enum.sort() ==
             Enum.sort(Enum.map(ViewDefinition.build(Organization).views, & &1.name))
  end

  test "a graph without views has no views and an empty definition" do
    assert ProjectedOrganization.__chronicle_graph__(:views) == []

    assert ViewDefinition.build(ProjectedOrganization) ==
             %{graph: "Organization", views: []}

    assert ViewDefinition.encode(ProjectedOrganization) ==
             "{\n  \"graph\": \"Organization\",\n  \"views\": []\n}\n"
  end

  test "views do not change what the graph registers" do
    assert Chronicle.Graphs.SchemaWriter.write(Organization) ==
             Chronicle.Graphs.SchemaWriter.write(without_views())

    assert Organization.__chronicle_graph__(:nodes) |> Enum.map(& &1.label) == ["Person", "Group"]
    assert Organization.__chronicle_graph__(:events) == []
  end

  test "is discovered like any other graph" do
    assert function_exported?(Organization, :__chronicle_graph__, 1)
  end

  test "a graph module may define its own view function" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Chronicle.Graphs.GraphViewsTest.OwnView#{System.unique_integer([:positive])} do
        use Chronicle.Graphs.Graph, id: "Own"

        def view(value), do: value
      end
      """)

    assert module.view(1) == 1
  end

  defp without_views do
    [{module, _}] =
      Code.compile_string("""
      defmodule Chronicle.Graphs.GraphViewsTest.Plain#{System.unique_integer([:positive])} do
        use Chronicle.Graphs.Graph, id: "Organization"
        alias Chronicle.GraphViewFixtures.{Group, HasRole, MemberOf, PartOf, Person}

        node Person, key: :person_id do
        end

        node Group, key: :group_id do
        end

        edge MemberOf, source: Person, target: Group do
        end

        edge PartOf, source: Group, target: Group do
        end

        edge HasRole, source: Person, target: Group, identified_by: :assignment_id do
        end
      end
      """)

    module
  end
end
