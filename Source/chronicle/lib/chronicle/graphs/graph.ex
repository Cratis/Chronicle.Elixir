# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Graphs.Graph do
  @moduledoc """
  Projects events onto a **property graph**: nodes, edges and their properties.

  A graph projection works like a projection onto a read model - the same observer, event
  routing, key and property expressions, replay and failed partition handling - but its target
  is a graph, stored by a graph sink such as Neo4j. Instead of folding events into one document
  per key, every event becomes a few idempotent operations on nodes and edges. The graph is what
  the events leave behind; nothing writes to it directly.

      defmodule MyApp.Graphs.Organization do
        use Chronicle.Graphs.Graph, id: "Organization"

        node MyApp.Graphs.Person, key: :person_id do
          from MyApp.Events.PersonRegistered, key: :person_id, set: [name: :name]
          removed_with MyApp.Events.PersonRemoved, key: :person_id, detach: true
        end

        node MyApp.Graphs.Group, key: :group_id do
          from MyApp.Events.GroupCreated, key: :group_id
          from MyApp.Events.MemberAdded, key: :group_id, increment: :member_count
          from MyApp.Events.MemberRemoved, key: :group_id, decrement: :member_count
        end

        edge MyApp.Graphs.MemberOf, source: MyApp.Graphs.Person, target: MyApp.Graphs.Group do
          from MyApp.Events.MemberAdded,
            source_key: :person_id,
            target_key: :group_id,
            set: [since: {:event_context, :occurred}]

          removed_with MyApp.Events.MemberRemoved, source_key: :person_id, target_key: :group_id
        end
      end

  The node and edge types are structs that `use Chronicle.Graphs.Node` and
  `use Chronicle.Graphs.Edge`:

      defmodule MyApp.Graphs.Person do
        use Chronicle.Graphs.Node
        defstruct person_id: "", name: ""
      end

      defmodule MyApp.Graphs.MemberOf do
        use Chronicle.Graphs.Edge, type: "MEMBER_OF"
        defstruct since: ""
      end

  ## Options

    * `:id` - the name of the graph. It is also the identifier of the projection and of the
      read model the graph is registered as. Defaults to the last segment of the module name.

  ## Nodes

  `node/3` adds a node type to the graph. `key:` names the field of the node struct that holds
  its unique key and is required. Inside the block:

    * `from/2` projects an event onto the node. `key:` names the event property holding the
      node's key and defaults to the event source id. The properties of the node are mapped from
      the event property of the same name, or explicitly with the options below. `update_only:
      true` changes the node only when it already exists.
    * `removed_with/2` deletes the node when the event occurs. A node that still has edges
      cannot be deleted unless `detach: true` deletes those edges with it.

  ## Edges

  `edge/3` adds an edge type that connects two nodes of the graph. `source:` and `target:` name
  the node modules, which must be declared with `node` in the same graph. By default an edge is
  identified by its type, source and target, so there is at most one edge of a type between two
  nodes. `identified_by:` names a field of the edge struct that allows several edges between the
  same two nodes; every `from` and `removed_with` of the edge then reads that field from the
  event property of the same name, or from the one `identity:` names. Inside the block:

    * `from/2` projects an event onto the edge. `source_key:` and `target_key:` name the event
      properties holding the keys of the end nodes and default to the event source id. An edge
      operation creates a bare end node when it does not exist.
    * `removed_with/2` deletes the edge when the event occurs. The nodes at both ends stay. An
      edge cannot `detach`.

  ## Property options

  `from/2` takes the same options as the read model projections:

    * `:set` - `[field: expression]`, where the expression is an event property (`:name`), the
      event source id (`:event_source_id`), an event context property
      (`{:event_context, :occurred}`) or a constant (`{:value, "x"}`, `true`, `42`).
    * `:add` and `:subtract` - `[field: :event_property]`, adding or subtracting the event
      property to or from the field.
    * `:increment`, `:decrement` and `:count` - a field, or a list of fields, that is
      incremented, decremented or counted on every event.
    * `:clear` - a field, or a list of fields, that is set back to no value.

  Counters apply to node and edge properties alike.

  ## Compile-time errors

  A graph that cannot work does not compile. The compiler raises a `CompileError` pointing at
  the offending line when:

    * an edge names a source or target that is not declared as a node of the graph
    * a node has no `key:`, or the key is not a field of the node struct
    * an edge `removed_with` asks to `detach`, which only a node can do
    * a node or edge struct has a nested struct or a map property - a property is a primitive
      or a list of primitives
    * an edge is `identified_by` a field, but an event neither names it with `identity:` nor has
      a property of that name
    * an option is unknown, a mapped field is not a field of the struct, a module is not a
      node, edge or event type, or an element is declared twice

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        graphs: [MyApp.Graphs.Organization]}

  Or use `otp_app:` auto-discovery - modules that export `__chronicle_graph__/1` are discovered
  automatically. The graph is registered as a read model stored by the graph sink, and as a
  projection, through the same registration coordinator as every other projection. The sink is
  set per client with `:default_graph_sink_type_id`, which defaults to `:neo4j`; see
  `Chronicle.Sinks.WellKnownSinkTypes`.

  ## Introspection

      MyApp.Graphs.Organization.__chronicle_graph__(:id)
      MyApp.Graphs.Organization.__chronicle_graph__(:nodes)
      MyApp.Graphs.Organization.__chronicle_graph__(:edges)
      MyApp.Graphs.Organization.__chronicle_graph__(:events)
  """

  alias Chronicle.Graphs.Compiler

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_graph_declarations, [])
      Module.register_attribute(__MODULE__, :chronicle_graph_open, [])

      @chronicle_graph_id Keyword.get(opts, :id, __MODULE__ |> Module.split() |> List.last())
      @chronicle_graph_file __ENV__.file
      @chronicle_graph_declarations []
      @chronicle_graph_open nil

      import Chronicle.Graphs.Graph,
        only: [
          node: 2,
          node: 3,
          edge: 2,
          edge: 3,
          from: 1,
          from: 2,
          removed_with: 1,
          removed_with: 2
        ]

      @before_compile Chronicle.Graphs.Graph
    end
  end

  @doc """
  Adds a node type to the graph.

  `key:` names the field of the node struct that holds its unique key. The block declares the
  events that create, change and remove the node with `from/2` and `removed_with/2`. See the
  module documentation.
  """
  defmacro node(module, opts, block \\ []) do
    declare(:node, module, opts, block, __CALLER__)
  end

  @doc """
  Adds an edge type that connects two nodes of the graph.

  `source:` and `target:` name the node modules, which must be declared in the same graph.
  `identified_by:` names a field of the edge struct that identifies the edge among several
  edges of the same type between the same two nodes. The block declares the events that create,
  change and remove the edge. See the module documentation.
  """
  defmacro edge(module, opts, block \\ []) do
    declare(:edge, module, opts, block, __CALLER__)
  end

  defp declare(kind, module, opts, block, caller) do
    # `node Person do ... end` has no options, so the block arrives where the options would.
    {opts, block} =
      if block == [] and Keyword.keyword?(opts) and Keyword.has_key?(opts, :do),
        do: {[], opts},
        else: {opts, block}

    body = Keyword.get(block, :do)

    quote do
      Chronicle.Graphs.Graph.__open__(
        __MODULE__,
        unquote(kind),
        unquote(module),
        unquote(opts),
        unquote(caller.line)
      )

      unquote(body)
      Chronicle.Graphs.Graph.__close__(__MODULE__)
    end
  end

  @doc """
  Projects an event onto the node or edge being declared.

  Only valid inside a `node` or `edge` block. See the module documentation for the options.
  """
  defmacro from(event_module, opts \\ []) do
    quote do
      Chronicle.Graphs.Graph.__add__(
        __MODULE__,
        :from,
        unquote(event_module),
        unquote(opts),
        unquote(__CALLER__.line)
      )
    end
  end

  @doc """
  Removes the node or edge being declared when the event occurs.

  Only valid inside a `node` or `edge` block. A node accepts `detach: true`, an edge does not.
  """
  defmacro removed_with(event_module, opts \\ []) do
    quote do
      Chronicle.Graphs.Graph.__add__(
        __MODULE__,
        :removed,
        unquote(event_module),
        unquote(opts),
        unquote(__CALLER__.line)
      )
    end
  end

  @doc false
  def __open__(module, kind, element, opts, line) do
    if Module.get_attribute(module, :chronicle_graph_open) do
      raise CompileError,
        file: file(module),
        line: line,
        description: "a node or edge cannot be declared inside another node or edge"
    end

    Module.put_attribute(module, :chronicle_graph_open, %{
      kind: kind,
      module: element,
      opts: opts,
      line: line,
      from: [],
      removed: []
    })
  end

  @doc false
  def __add__(module, which, event, opts, line) do
    case Module.get_attribute(module, :chronicle_graph_open) do
      nil ->
        raise CompileError,
          file: file(module),
          line: line,
          description:
            "#{if which == :from, do: "from", else: "removed_with"} #{inspect(event)} must be " <>
              "inside a node or edge block"

      open ->
        Module.put_attribute(
          module,
          :chronicle_graph_open,
          Map.update!(open, which, &(&1 ++ [{event, opts, line}]))
        )
    end
  end

  @doc false
  def __close__(module) do
    open = Module.get_attribute(module, :chronicle_graph_open)
    declarations = Module.get_attribute(module, :chronicle_graph_declarations)
    Module.put_attribute(module, :chronicle_graph_declarations, declarations ++ [open])
    Module.put_attribute(module, :chronicle_graph_open, nil)
  end

  defp file(module), do: Module.get_attribute(module, :chronicle_graph_file)

  @doc false
  defmacro __before_compile__(env) do
    declarations = Module.get_attribute(env.module, :chronicle_graph_declarations)
    %{nodes: nodes, edges: edges} = Compiler.compile!(env, declarations)

    events =
      Enum.flat_map(nodes ++ edges, &(&1.from ++ &1.removed_with))
      |> Enum.map(& &1.event)
      |> Enum.uniq()

    graph = %{nodes: nodes, edges: edges, events: events}

    quote do
      @doc false
      def __chronicle_graph__(:id), do: @chronicle_graph_id

      @doc false
      def __chronicle_graph__(:nodes), do: unquote(Macro.escape(graph.nodes))

      @doc false
      def __chronicle_graph__(:edges), do: unquote(Macro.escape(graph.edges))

      @doc false
      def __chronicle_graph__(:events), do: unquote(Macro.escape(graph.events))
    end
  end
end
