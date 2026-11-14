---
title: Graph projections
description: Project events onto a property graph with the Elixir client's node and edge DSL, see what the compiler checks, and register the graph with Chronicle.
---

See [Graph projections](/chronicle/projections/graph-projections/) for what a graph projection is: how nodes, edges and their properties are projected, the five idempotent operations a graph sink applies, redelivery and replay, and the sinks. This page covers the Elixir client: the `node` and `edge` DSL, what the compiler checks, and how a graph is registered.

A graph is a module that `use Chronicle.Graphs.Graph`. Its nodes and edges are structs that `use Chronicle.Graphs.Node` and `use Chronicle.Graphs.Edge`, and the graph says which events create, change and remove each of them.

```elixir
defmodule MyApp.Graphs.Person do
  use Chronicle.Graphs.Node
  defstruct person_id: "", name: ""
end

defmodule MyApp.Graphs.Group do
  use Chronicle.Graphs.Node
  defstruct group_id: "", name: ""
end

defmodule MyApp.Graphs.MemberOf do
  use Chronicle.Graphs.Edge, type: "MEMBER_OF"
  defstruct since: ""
end

defmodule MyApp.Graphs.Organization do
  use Chronicle.Graphs.Graph, id: "Organization"

  node MyApp.Graphs.Person, key: :person_id do
    from MyApp.Events.PersonRegistered, key: :person_id, set: [name: :name]
    removed_with MyApp.Events.PersonRemoved, key: :person_id, detach: true
  end

  node MyApp.Graphs.Group, key: :group_id do
    from MyApp.Events.GroupCreated, key: :group_id
  end

  edge MyApp.Graphs.MemberOf, source: MyApp.Graphs.Person, target: MyApp.Graphs.Group do
    from MyApp.Events.MemberAdded,
      source_key: :person_id,
      target_key: :group_id,
      set: [since: {:event_context, :occurred}]

    removed_with MyApp.Events.MemberRemoved, source_key: :person_id, target_key: :group_id
  end
end
```

The graph is what the events leave behind. Nothing writes to it directly.

## Nodes and edges

The struct fields are the properties, typed by their `defstruct` defaults. A property is a primitive or a list of primitives. The label of a node and the type of an edge default to the last segment of the module name; `use Chronicle.Graphs.Node, label: "Employee"` and `use Chronicle.Graphs.Edge, type: "MEMBER_OF"` choose another one. Property names are the `camelCase` of the field names, the way the .NET client names them, so the same graph registers the same definition from either client.

`node/3` names the field that holds the unique key with `key:`. `edge/3` names the two nodes it connects with `source:` and `target:`; both must be declared with `node` in the same graph. The two end nodes are not properties of the edge.

Inside the block:

- `from/2` projects an event onto the node or edge. A node takes `key:`, an edge takes `source_key:` and `target_key:`, naming the event properties that hold the keys. Each defaults to the event source id. A property is mapped from the event property of the same name, or explicitly with the options below.
- `removed_with/2` deletes the node or edge when the event occurs. A node accepts `detach: true`, which deletes its edges with it; without it a node that still has edges cannot be deleted. An edge cannot detach.
- `update_only: true` on a node's `from` changes the node only when it already exists.

## Property options

`from/2` takes the options of the read model projections:

| Option | Meaning |
| --- | --- |
| `set: [field: expression]` | Sets the field from an event property (`:name`), the event source id (`:event_source_id`), an event context property (`{:event_context, :occurred}`) or a constant (`{:value, "x"}`, `true`, `42`). |
| `add: [field: :property]`, `subtract: [field: :property]` | Adds or subtracts the event property to or from the field. |
| `increment:`, `decrement:`, `count:` | A field or a list of fields that is incremented, decremented or counted on every event. |
| `clear:` | A field or a list of fields that is set back to no value. |

Counters work on node and edge properties alike.

## Counters

```elixir
node MyApp.Graphs.Team, key: :team_id do
  from MyApp.Events.TeamFormed, key: :team_id
  from MyApp.Events.TeamMemberJoined, key: :team_id, increment: :member_count
  from MyApp.Events.TeamMemberLeft, key: :team_id, decrement: :member_count
end
```

## Edges with an identity

By default an edge is identified by its type, source and target. `identified_by:` names a field of the edge struct that identifies it among several edges of the same type between the same two nodes. Every `from` and `removed_with` of the edge then has to say which event property holds the identity: the one named like the field, or the one `identity:` names. A sink that cannot hold several edges between the same pair of nodes rejects such an edge type.

```elixir
edge MyApp.Graphs.Visited,
  source: MyApp.Graphs.Customer,
  target: MyApp.Graphs.Shop,
  identified_by: :visit_id do
  from MyApp.Events.ShopVisited, source_key: :customer_id, target_key: :shop_id, count: :times
end
```

## What the compiler checks

A graph that cannot work does not compile. The `CompileError` names the line of the declaration when:

- an edge names a source or target that is not declared as a node of the graph
- a node has no `key:`, or its key is not a field of the node struct
- an edge's `removed_with` asks to `detach`
- a node or edge struct has a nested struct or a map property
- an identified edge has an event that neither names the identity with `identity:` nor has a property of the same name
- a mapped field is not a field of the struct, an option is unknown, or a module is not a node, an edge or an event type

## Registering a graph

Add the graph module to `:graphs`, or let `otp_app:` discovery find it:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  graphs: [MyApp.Graphs.Organization]}
```

The client registers the graph as a read model stored by the graph sink, and as the projection that fills it, through the same registration coordinator as every other projection. The `id:` of the graph is the name of the read model and the identifier of the projection; pin it, because renaming it makes Chronicle treat the graph as a different projection.

## Choosing the sink

A graph is stored by a graph sink. Set the sink per client with `:default_graph_sink_type_id`, which defaults to `:neo4j`. Use `:in_memory_graph` for development and tests.

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  default_graph_sink_type_id: :in_memory_graph,
  graphs: [MyApp.Graphs.Organization]}
```

`:default_sink_type_id` keeps choosing the sink of document read models; it does not apply to graphs. See [Sinks](./sinks.md).

## Read a graph with views

A graph view is a read model over the graph: it is anchored at one node, and its members are properties of that node, relations along declared edges to other views, or properties of the edge that was followed. See [Graph projections](/chronicle/projections/graph-projections/) for the shared description of views and their rules.

Elixir structs carry no field types, so a view is a module that `use Chronicle.Graphs.View` with the node it is anchored at, and declares its members with `property`, `relation` and `edge_property`. The graph lists its views with `view`:

```elixir
defmodule MyApp.Directory.GroupMembership do
  use Chronicle.Graphs.View, root: MyApp.Directory.Group

  property :id, source: :group_id
  property :name
  edge_property :since
end

defmodule MyApp.Directory.PersonWithGroups do
  use Chronicle.Graphs.View, root: MyApp.Directory.Person

  property :id, source: :person_id
  property :name

  relation :groups, MyApp.Directory.MemberOf,
    view: MyApp.Directory.GroupMembership,
    cardinality: :many
end

defmodule MyApp.Directory.Graph do
  use Chronicle.Graphs.Graph, id: "Directory"

  # nodes and edges ...

  view MyApp.Directory.PersonWithGroups
  view MyApp.Directory.GroupMembership
end
```

- A member is named by the `camelCase` of its atom. `property` and `edge_property` match a property of the node or the edge by name, ignoring case, or by `source:`.
- `relation` takes the edge module (or its type string), the target `view:` and a required `cardinality:` of `:many` or `:one`. The direction is derived from the root for an edge between two different nodes; a self edge needs `direction: :outgoing` or `direction: :incoming`.
- A view takes its name from the last segment of its module name. `name:` chooses another one; names are unique in a graph.

A view that cannot work does not compile. The `CompileError` of the graph starts its description with one of the reasons `ViewRootNotANode`, `ViewIsAlsoSchema`, `DuplicateViewName`, `UnknownNodeProperty`, `UnknownEdge`, `UnknownEdgeProperty`, `EdgeNotIncidentOnRoot`, `AmbiguousDirection`, `TargetLabelMismatch`, `RelationTargetNotAView`, `RecursiveView`, `EdgePropertyViewNotUsedAsTarget` or `EdgePropertyViewSharedAcrossEdges`, for example `UnknownEdge: relation :groups of view PersonWithGroups ...`. `Chronicle.Graphs.View` lists what each one means.

The views of a graph are available as the `GraphViewDefinition` every Chronicle client emits for its views:

```elixir
Chronicle.Graphs.ViewDefinition.build(MyApp.Directory.Graph)
Chronicle.Graphs.ViewDefinition.encode(MyApp.Directory.Graph)
```

`build/1` returns the definition as plain data and `encode/1` the canonical JSON. A graph without views has an empty definition.

Views change nothing about what the graph registers: the definition is not sent to Chronicle, and a graph with views registers the same read model and projection as the graph without them. The Elixir client has no read side for views yet, so declaring a view validates it and produces its definition, but there is no function that runs a query over it.

## What the Elixir client does not do yet

- Reading the graph, with or without views. Applications read it with the engine driver, as the shared page describes; a view is validated and emitted as a definition, not executed.
- A test harness. `Chronicle.Testing` has no graph scenario yet, so a graph is tested by asserting the definition it registers.
