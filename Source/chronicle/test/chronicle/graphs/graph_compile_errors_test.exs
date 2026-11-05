# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.GraphCompileErrorsTest do
  use ExUnit.Case, async: true

  # Every graph below is compiled from a string so the error and the line it points at can be
  # asserted. The short names are the Organization fixtures, which are valid on their own.
  @fixtures ~w(Group MemberAdded MemberOf MemberRemoved Person PersonRegistered PersonRemoved Place PlaceVisited Visited)

  defp compile_graph(body, name \\ "Graph") do
    module =
      "Chronicle.Graphs.GraphCompileErrorsTest.#{name}#{System.unique_integer([:positive])}"

    body =
      Regex.replace(
        ~r/(?<![\w.])(#{Enum.join(@fixtures, "|")})(?![\w.])/,
        body,
        "Chronicle.GraphFixtures.\\1"
      )

    Code.compile_string("""
    defmodule #{module} do
      use Chronicle.Graphs.Graph, id: "Test"
    #{body}
    end
    """)
  end

  defp error_of(body) do
    assert_raise CompileError, fn -> compile_graph(body) end
  end

  test "compiles a valid graph" do
    assert [{_module, _binary}] =
             compile_graph("""
             node Person, key: :person_id do
               from PersonRegistered, key: :person_id
             end
             """)
  end

  test "rejects an edge whose endpoint is not a declared node" do
    error =
      error_of("""
      node Person, key: :person_id do
        from PersonRegistered, key: :person_id
      end

      edge MemberOf, source: Person, target: Group do
        from MemberAdded, source_key: :person_id, target_key: :group_id
      end
      """)

    assert error.description =~ "target Chronicle.GraphFixtures.Group"
    assert error.description =~ "not declared as a node"
  end

  test "rejects an edge that does not name its endpoints" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      edge MemberOf, source: Person do
      end
      """)

    assert error.description =~ "needs a target"
  end

  test "rejects detach on an edge" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      node Group, key: :group_id do
      end

      edge MemberOf, source: Person, target: Group do
        removed_with MemberRemoved, source_key: :person_id, target_key: :group_id, detach: true
      end
      """)

    assert error.description =~ "cannot detach"
  end

  test "rejects a node without a key" do
    error =
      error_of("""
      node Person do
        from PersonRegistered
      end
      """)

    assert error.description =~ "needs a key"
  end

  test "rejects a node whose key is not a field of its struct" do
    error =
      error_of("""
      node Person, key: :identifier do
      end
      """)

    assert error.description =~ "key :identifier"
    assert error.description =~ "not a field"
  end

  test "rejects a nested struct property" do
    defmodule Address do
      defstruct street: ""
    end

    defmodule PersonWithAddress do
      use Chronicle.Graphs.Node
      defstruct person_id: "", address: %Address{}
    end

    error =
      error_of("""
      node #{inspect(PersonWithAddress)}, key: :person_id do
      end
      """)

    assert error.description =~ "property :address"
    assert error.description =~ "nested struct or map"
  end

  test "rejects a map property" do
    defmodule PersonWithMap do
      use Chronicle.Graphs.Node
      defstruct person_id: "", attributes: %{}
    end

    error =
      error_of("""
      node #{inspect(PersonWithMap)}, key: :person_id do
      end
      """)

    assert error.description =~ "property :attributes"
  end

  test "accepts lists of primitives as properties" do
    defmodule PersonWithTags do
      use Chronicle.Graphs.Node
      defstruct person_id: "", tags: ["a"], scores: [1, 2], active: true, joined: nil
    end

    assert [{_module, _binary}] =
             compile_graph("""
             node #{inspect(PersonWithTags)}, key: :person_id do
             end
             """)
  end

  test "rejects a list of nested structs as a property" do
    defmodule Address2 do
      defstruct street: ""
    end

    defmodule PersonWithAddresses do
      use Chronicle.Graphs.Node
      defstruct person_id: "", addresses: [%Address2{}]
    end

    error =
      error_of("""
      node #{inspect(PersonWithAddresses)}, key: :person_id do
      end
      """)

    assert error.description =~ "property :addresses"
  end

  test "rejects an identified edge whose event has no identity" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      node Place, key: :place_id do
      end

      edge Visited, source: Person, target: Place, identified_by: :visit_id do
        from MemberAdded, source_key: :person_id, target_key: :group_id
      end
      """)

    assert error.description =~ "identified by :visit_id"
    assert error.description =~ "identity:"
  end

  test "takes the identity of an edge from an explicit event property" do
    assert [{_module, _binary}] =
             compile_graph("""
             node Person, key: :person_id do
             end

             node Place, key: :place_id do
             end

             edge Visited, source: Person, target: Place, identified_by: :visit_id do
               from MemberAdded, source_key: :person_id, target_key: :group_id, identity: :person_id
             end
             """)
  end

  test "rejects identified_by a field the edge does not have" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      node Place, key: :place_id do
      end

      edge Visited, source: Person, target: Place, identified_by: :ticket do
      end
      """)

    assert error.description =~ "identified_by :ticket"
  end

  test "rejects an identity on an edge that is not identified" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      node Group, key: :group_id do
      end

      edge MemberOf, source: Person, target: Group do
        from MemberAdded, source_key: :person_id, target_key: :group_id, identity: :person_id
      end
      """)

    assert error.description =~ "identified_by"
  end

  test "rejects mapping a field that is not a property" do
    error =
      error_of("""
      node Person, key: :person_id do
        from PersonRegistered, key: :person_id, set: [nickname: :name]
      end
      """)

    assert error.description =~ ":nickname is not a property"
  end

  test "rejects an option it does not know" do
    error =
      error_of("""
      node Person, key: :person_id do
        from PersonRegistered, key: :person_id, source_key: :person_id
      end
      """)

    assert error.description =~ ":source_key"
  end

  test "rejects from outside a node or edge" do
    error = error_of("from PersonRegistered, key: :person_id")
    assert error.description =~ "inside a node or edge block"
  end

  test "rejects a module that is not a node" do
    error =
      error_of("""
      node PersonRegistered, key: :person_id do
      end
      """)

    assert error.description =~ "must `use Chronicle.Graphs.Node`"
  end

  test "rejects an event that is not an event type" do
    error =
      error_of("""
      node Person, key: :person_id do
        from Person, key: :person_id
      end
      """)

    assert error.description =~ "is not an event type"
  end

  test "rejects the same event twice on one node" do
    error =
      error_of("""
      node Person, key: :person_id do
        from PersonRegistered, key: :person_id
        from PersonRegistered, key: :person_id, set: [name: :name]
      end
      """)

    assert error.description =~ "more than once"
  end

  test "rejects the same node twice" do
    error =
      error_of("""
      node Person, key: :person_id do
      end

      node Person, key: :person_id do
      end
      """)

    assert error.description =~ ~s(node label "Person" is declared more than once)
  end

  test "points the error at the offending line" do
    error =
      error_of("""
      node Person, key: :person_id do
        removed_with PersonRemoved, key: :person_id
        from PersonRegistered, key: :person_id, set: [nickname: :name]
      end
      """)

    # The wrapper takes 2 lines before the body starts; the bad `from` is the 3rd line of it.
    assert error.line == 5
  end
end
