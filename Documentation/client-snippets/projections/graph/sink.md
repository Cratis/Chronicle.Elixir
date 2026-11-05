```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  # Neo4j is the default. The in-memory graph sink keeps the graph in the kernel's memory.
  default_graph_sink_type_id: :in_memory_graph,
  graphs: [MyApp.Graphs.Organization]}
```
