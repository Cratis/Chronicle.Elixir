```elixir
defmodule MyApp.Events.PersonRegistered do
  use Chronicle.Events.EventType, id: "graph-person-registered"
  defstruct person_id: "", name: ""
end

defmodule MyApp.Events.PersonRemoved do
  use Chronicle.Events.EventType, id: "graph-person-removed"
  defstruct person_id: ""
end

defmodule MyApp.Events.GroupCreated do
  use Chronicle.Events.EventType, id: "graph-group-created"
  defstruct group_id: "", name: ""
end

defmodule MyApp.Events.MemberAdded do
  use Chronicle.Events.EventType, id: "graph-member-added"
  defstruct person_id: "", group_id: ""
end

defmodule MyApp.Events.MemberRemoved do
  use Chronicle.Events.EventType, id: "graph-member-removed"
  defstruct person_id: "", group_id: ""
end

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

  alias MyApp.Events.{GroupCreated, MemberAdded, MemberRemoved, PersonRegistered, PersonRemoved}
  alias MyApp.Graphs.{Group, MemberOf, Person}

  node Person, key: :person_id do
    from PersonRegistered, key: :person_id, set: [name: :name]
    removed_with PersonRemoved, key: :person_id, detach: true
  end

  node Group, key: :group_id do
    from GroupCreated, key: :group_id
  end

  edge MemberOf, source: Person, target: Group do
    from MemberAdded,
      source_key: :person_id,
      target_key: :group_id,
      set: [since: {:event_context, :occurred}]

    removed_with MemberRemoved, source_key: :person_id, target_key: :group_id
  end
end
```
