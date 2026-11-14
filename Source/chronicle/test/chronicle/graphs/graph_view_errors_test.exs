# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.GraphViewErrorsTest do
  use ExUnit.Case, async: true

  # Every graph is compiled from a string so the rejection can be asserted. `NS` becomes a
  # namespace that is unique to the spec, so the specs can run in parallel. Person, Group, Place,
  # MemberOf, PartOf and HasRole are the fixtures of the Organization graph.
  @preamble "alias Chronicle.GraphViewFixtures.{Group, HasRole, MemberOf, PartOf, Person, Place}, warn: false\n"

  defp compile(source) do
    namespace = "GraphViewErrors.N#{System.unique_integer([:positive])}"
    Code.compile_string(@preamble <> String.replace(source, "NS", namespace))
  end

  defp reason_of(source) do
    error = assert_raise CompileError, fn -> compile(source) end
    assert [_, reason] = Regex.run(~r/^(\w+): /, error.description)
    {reason, error}
  end

  # The two nodes and the three edges of the Organization graph, in a graph that declares the
  # views listed after it.
  defp graph(views, extra \\ "") do
    """
    defmodule NS.Graph do
      use Chronicle.Graphs.Graph, id: "Test"
      alias NS.Views

      node Person, key: :person_id do
      end

      node Group, key: :group_id do
      end

      node Place, key: :place_id do
      end

      edge MemberOf, source: Person, target: Group do
      end

      edge PartOf, source: Group, target: Group do
      end

      edge HasRole, source: Person, target: Group, identified_by: :assignment_id do
      end
      #{extra}
    #{Enum.map_join(views, "\n", &"  view Views.#{&1}")}
    end
    """
  end

  test "accepts a valid view" do
    assert [_, _] =
             compile("""
             defmodule NS.Views.Summary do
               use Chronicle.Graphs.View, root: Person
               property :id, source: :person_id
               property :NAME
             end

             #{graph(["Summary"])}
             """)
  end

  test "ViewRootNotANode" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Lonely do
        use Chronicle.Graphs.View, root: Chronicle.GraphViewFixtures.Place
        property :id, source: :place_id
      end

      defmodule NS.Graph do
        use Chronicle.Graphs.Graph, id: "Test"
        node Person, key: :person_id do
        end
        view NS.Views.Lonely
      end
      """)

    assert reason == "ViewRootNotANode"
  end

  test "ViewIsAlsoSchema" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Both do
        use Chronicle.Graphs.Node
        use Chronicle.Graphs.View, root: Person
        defstruct person_id: ""
      end

      #{graph(["Both"])}
      """)

    assert reason == "ViewIsAlsoSchema"
  end

  test "ViewIsAlsoSchema for a view that is an edge" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.AnEdge do
        use Chronicle.Graphs.Edge, type: "AN_EDGE"
        use Chronicle.Graphs.View, root: Person
        defstruct []
      end

      #{graph(["AnEdge"])}
      """)

    assert reason == "ViewIsAlsoSchema"
  end

  test "DuplicateViewName" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
      end

      defmodule NS.Other.Summary do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
      end

      defmodule NS.Graph do
        use Chronicle.Graphs.Graph, id: "Test"
        node Person, key: :person_id do
        end
        node Group, key: :group_id do
        end
        view NS.Views.Summary
        view NS.Other.Summary
      end
      """)

    assert reason == "DuplicateViewName"
  end

  test "a view can be given another name to avoid a duplicate" do
    assert compile("""
           defmodule NS.Views.Summary do
             use Chronicle.Graphs.View, root: Person
             property :id, source: :person_id
           end

           defmodule NS.Other.Summary do
             use Chronicle.Graphs.View, root: Group, name: "GroupSummary"
             property :id, source: :group_id
           end

           defmodule NS.Graph do
             use Chronicle.Graphs.Graph, id: "Test"
             node Person, key: :person_id do
             end
             node Group, key: :group_id do
             end
             view NS.Views.Summary
             view NS.Other.Summary
           end
           """)
  end

  test "UnknownNodeProperty" do
    {reason, error} =
      reason_of("""
      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        property :nickname
      end

      #{graph(["Summary"])}
      """)

    assert reason == "UnknownNodeProperty"
    assert error.description =~ "nickname"
  end

  test "UnknownEdge" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :friends, "FRIEND_OF", view: NS.Views.Summary, cardinality: :many
      end

      #{graph(["Summary"])}
      """)

    assert reason == "UnknownEdge"
  end

  test "UnknownEdge for an edge module the graph does not declare" do
    {reason, _} =
      reason_of("""
      defmodule NS.Visited do
        use Chronicle.Graphs.Edge, type: "VISITED"
        defstruct []
      end

      defmodule NS.Views.Target do
        use Chronicle.Graphs.View, root: Place
        property :id, source: :place_id
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :visited, NS.Visited, view: NS.Views.Target, cardinality: :many
      end

      #{graph(["Summary", "Target"])}
      """)

    assert reason == "UnknownEdge"
  end

  test "UnknownEdgeProperty" do
    {reason, error} =
      reason_of("""
      defmodule NS.Views.Membership do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        edge_property :until
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.Membership, cardinality: :many
      end

      #{graph(["Summary", "Membership"])}
      """)

    assert reason == "UnknownEdgeProperty"
    assert error.description =~ "until"
  end

  test "EdgeNotIncidentOnRoot" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Target do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Place
        property :id, source: :place_id
        relation :groups, MemberOf, view: NS.Views.Target, cardinality: :many
      end

      #{graph(["Summary", "Target"])}
      """)

    assert reason == "EdgeNotIncidentOnRoot"
  end

  test "EdgeNotIncidentOnRoot for an explicit direction the root contradicts" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Target do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.Target, cardinality: :many, direction: :incoming
      end

      #{graph(["Summary", "Target"])}
      """)

    assert reason == "EdgeNotIncidentOnRoot"
  end

  test "AmbiguousDirection" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        relation :parent, PartOf, view: NS.Views.Summary, cardinality: :one
      end

      #{graph(["Summary"])}
      """)

    assert reason == "AmbiguousDirection"
  end

  test "TargetLabelMismatch" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.PersonSummary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.PersonSummary, cardinality: :many
      end

      #{graph(["Summary", "PersonSummary"])}
      """)

    assert reason == "TargetLabelMismatch"
  end

  test "RelationTargetNotAView" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Target do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.Target, cardinality: :many
      end

      #{graph(["Summary"])}
      """)

    assert reason == "RelationTargetNotAView"
  end

  test "RecursiveView directly" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Tree do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        relation :parent, PartOf, view: NS.Views.Tree, cardinality: :one, direction: :outgoing
      end

      #{graph(["Tree"])}
      """)

    assert reason == "RecursiveView"
  end

  test "RecursiveView through another view" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.PersonWithGroups do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.GroupWithMembers, cardinality: :many
      end

      defmodule NS.Views.GroupWithMembers do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        relation :members, MemberOf, view: NS.Views.PersonWithGroups, cardinality: :many
      end

      #{graph(["PersonWithGroups", "GroupWithMembers"])}
      """)

    assert reason == "RecursiveView"
  end

  test "EdgePropertyViewNotUsedAsTarget" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Membership do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        edge_property :since
      end

      #{graph(["Membership"])}
      """)

    assert reason == "EdgePropertyViewNotUsedAsTarget"
  end

  test "EdgePropertyViewSharedAcrossEdges" do
    {reason, _} =
      reason_of("""
      defmodule NS.Views.Shared do
        use Chronicle.Graphs.View, root: Group
        property :id, source: :group_id
        edge_property :since
      end

      defmodule NS.Views.Summary do
        use Chronicle.Graphs.View, root: Person
        property :id, source: :person_id
        relation :groups, MemberOf, view: NS.Views.Shared, cardinality: :many
        relation :roles, HasRole, view: NS.Views.Shared, cardinality: :many
      end

      #{graph(["Summary", "Shared"])}
      """)

    assert reason == "EdgePropertyViewSharedAcrossEdges"
  end

  test "an edge property view may be the target of several relations of one edge" do
    assert compile("""
           defmodule NS.Views.Membership do
             use Chronicle.Graphs.View, root: Group
             property :id, source: :group_id
             edge_property :since
           end

           defmodule NS.Views.Summary do
             use Chronicle.Graphs.View, root: Person
             property :id, source: :person_id
             relation :groups, MemberOf, view: NS.Views.Membership, cardinality: :many
             relation :first_groups, "MEMBER_OF", view: NS.Views.Membership, cardinality: :one
           end

           #{graph(["Summary", "Membership"])}
           """)
  end

  test "rejects an invalid view declaration where it is declared" do
    for {body, message} <- [
          {"use Chronicle.Graphs.View, name: \"X\"", "needs a root"},
          {"use Chronicle.Graphs.View, root: Person, colour: 1", "does not support :colour"},
          {"use Chronicle.Graphs.View, root: Person\nproperty :id\nproperty :id",
           "declared more than once"},
          {"use Chronicle.Graphs.View, root: Person\nrelation :g, MemberOf, view: Person",
           "cardinality"},
          {"use Chronicle.Graphs.View, root: Person\nrelation :g, MemberOf, cardinality: :many",
           "needs `view:`"},
          {"use Chronicle.Graphs.View, root: Person\nproperty :id, size: 1",
           "does not support :size"}
        ] do
      error =
        assert_raise CompileError, fn ->
          compile("defmodule NS.Bad do\n#{body}\nend")
        end

      assert error.description =~ message
    end
  end

  test "rejects a view declared inside a node" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule NS.Graph do
          use Chronicle.Graphs.Graph, id: "Test"

          node Person, key: :person_id do
            view NS.Views.Anything
          end
        end
        """)
      end

    assert error.description =~ "inside a node or edge"
  end
end
