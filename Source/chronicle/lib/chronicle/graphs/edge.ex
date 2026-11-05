# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.Edge do
  @moduledoc """
  Marks a struct as an edge type of a property graph.

  The struct's fields are the properties of the edge, typed by their `defstruct` defaults
  (primitives and lists of primitives only). The two end nodes are not properties: they are
  named where the edge is added to a graph, with `Chronicle.Graphs.Graph.edge/3`.

      defmodule MyApp.Graphs.MemberOf do
        use Chronicle.Graphs.Edge, type: "MEMBER_OF"
        defstruct since: ""
      end

  ## Options

    * `:type` - the edge type, for example `"MEMBER_OF"`. Defaults to the last segment of the
      module name, as the .NET client names an edge after its type.

  ## Introspection

      MyApp.Graphs.MemberOf.__chronicle_graph_edge__(:type)
      #=> "MEMBER_OF"
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @chronicle_graph_edge_type Keyword.get(
                                   opts,
                                   :type,
                                   __MODULE__ |> Module.split() |> List.last()
                                 )

      @doc false
      def __chronicle_graph_edge__(:type), do: @chronicle_graph_edge_type
    end
  end
end
