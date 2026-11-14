```elixir
defmodule MyApp.Directory.Person do
  use Chronicle.Graphs.Node
  defstruct person_id: "", name: ""
end

defmodule MyApp.Directory.Group do
  use Chronicle.Graphs.Node
  defstruct group_id: "", name: ""
end

defmodule MyApp.Directory.MemberOf do
  use Chronicle.Graphs.Edge, type: "MEMBER_OF"
  defstruct since: ""
end

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

  alias MyApp.Directory.{Group, MemberOf, Person, GroupMembership, PersonWithGroups}

  node Person, key: :person_id do
  end

  node Group, key: :group_id do
  end

  edge MemberOf, source: Person, target: Group do
  end

  view PersonWithGroups
  view GroupMembership
end
```
