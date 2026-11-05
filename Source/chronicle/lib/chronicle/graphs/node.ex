# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.Node do
  @moduledoc """
  Marks a struct as a node type of a property graph.

  The struct's fields are the properties of the node and their `defstruct` defaults give
  their types: a primitive (string, number, boolean) or a list of primitives. A nested struct
  or map is a compile error when the node is declared in a graph, because a property graph
  holds primitives only - model the object as a node of its own and connect it with an edge.

      defmodule MyApp.Graphs.Person do
        use Chronicle.Graphs.Node
        defstruct person_id: "", name: ""
      end

  The node **label** is the last segment of the module name (`"Person"`), exactly as the
  .NET client names a node after its type. Pass `:label` to choose another one:

      use Chronicle.Graphs.Node, label: "Employee"

  The key of the node is declared where the node is added to a graph, with
  `Chronicle.Graphs.Graph.node/3`.

  ## Introspection

      MyApp.Graphs.Person.__chronicle_graph_node__(:label)
      #=> "Person"
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @chronicle_graph_node_label Keyword.get(
                                    opts,
                                    :label,
                                    __MODULE__ |> Module.split() |> List.last()
                                  )

      @doc false
      def __chronicle_graph_node__(:label), do: @chronicle_graph_node_label
    end
  end
end
