# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# The Organization graph, the same one the .NET client specs declare in
# Source/Clients/DotNET.Specs/Projections/Graphs/for_GraphDefinitionBuilder/given (events,
# Person/Group/Place nodes, the MEMBER_OF edge and the VISITED edge identified by its visit).

defmodule Chronicle.GraphFixtures.PersonRegistered do
  use Chronicle.Events.EventType, id: "person-registered"
  defstruct person_id: "", name: ""
end

defmodule Chronicle.GraphFixtures.PersonRemoved do
  use Chronicle.Events.EventType, id: "person-removed"
  defstruct person_id: ""
end

defmodule Chronicle.GraphFixtures.GroupCreated do
  use Chronicle.Events.EventType, id: "group-created"
  defstruct group_id: "", name: ""
end

defmodule Chronicle.GraphFixtures.MemberAdded do
  use Chronicle.Events.EventType, id: "member-added"
  defstruct person_id: "", group_id: ""
end

defmodule Chronicle.GraphFixtures.MemberRemoved do
  use Chronicle.Events.EventType, id: "member-removed"
  defstruct person_id: "", group_id: ""
end

defmodule Chronicle.GraphFixtures.PlaceVisited do
  use Chronicle.Events.EventType, id: "place-visited"
  defstruct person_id: "", place_id: "", visit_id: ""
end

defmodule Chronicle.GraphFixtures.Person do
  use Chronicle.Graphs.Node
  defstruct person_id: "", name: ""
end

defmodule Chronicle.GraphFixtures.Group do
  use Chronicle.Graphs.Node
  defstruct group_id: "", name: "", member_count: 0
end

defmodule Chronicle.GraphFixtures.Place do
  use Chronicle.Graphs.Node
  defstruct place_id: ""
end

defmodule Chronicle.GraphFixtures.MemberOf do
  use Chronicle.Graphs.Edge, type: "MEMBER_OF"
  defstruct since: ""
end

defmodule Chronicle.GraphFixtures.Visited do
  use Chronicle.Graphs.Edge, type: "VISITED"
  defstruct visit_id: "", times: 0
end

defmodule Chronicle.GraphFixtures.Organization do
  use Chronicle.Graphs.Graph, id: "Organization"

  alias Chronicle.GraphFixtures.{
    Group,
    GroupCreated,
    MemberAdded,
    MemberOf,
    MemberRemoved,
    Person,
    PersonRegistered,
    PersonRemoved,
    Place,
    PlaceVisited,
    Visited
  }

  node Person, key: :person_id do
    from(PersonRegistered, key: :person_id)
    removed_with(PersonRemoved, key: :person_id, detach: true)
  end

  node Group, key: :group_id do
    from(GroupCreated, key: :group_id)
    from(MemberAdded, key: :group_id, increment: :member_count)
    from(MemberRemoved, key: :group_id, decrement: :member_count)
  end

  node Place, key: :place_id do
    from(PlaceVisited, key: :place_id)
  end

  edge MemberOf, source: Person, target: Group do
    from(MemberAdded,
      source_key: :person_id,
      target_key: :group_id,
      set: [since: {:event_context, :occurred}]
    )

    removed_with(MemberRemoved, source_key: :person_id, target_key: :group_id)
  end

  edge Visited, source: Person, target: Place, identified_by: :visit_id do
    from(PlaceVisited, source_key: :person_id, target_key: :place_id, count: :times)
  end
end
