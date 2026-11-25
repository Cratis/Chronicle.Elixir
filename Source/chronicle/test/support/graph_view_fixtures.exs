# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# The Organization graph of the shared graph views conformance fixture
# (test/fixtures/graphs/graph-views-organization.json), declared with its eight views. `Place` is
# a node that is not part of the Organization graph; the rejection specs use it.

defmodule Cratis.Chronicle.GraphViewFixtures.Person do
  use Cratis.Chronicle.Graphs.Node
  defstruct person_id: "", name: ""
end

defmodule Cratis.Chronicle.GraphViewFixtures.Group do
  use Cratis.Chronicle.Graphs.Node
  defstruct group_id: "", name: ""
end

defmodule Cratis.Chronicle.GraphViewFixtures.Place do
  use Cratis.Chronicle.Graphs.Node
  defstruct place_id: ""
end

defmodule Cratis.Chronicle.GraphViewFixtures.MemberOf do
  use Cratis.Chronicle.Graphs.Edge, type: "MEMBER_OF"
  defstruct since: ""
end

defmodule Cratis.Chronicle.GraphViewFixtures.PartOf do
  use Cratis.Chronicle.Graphs.Edge, type: "PART_OF"
  defstruct []
end

defmodule Cratis.Chronicle.GraphViewFixtures.HasRole do
  use Cratis.Chronicle.Graphs.Edge, type: "HAS_ROLE"
  defstruct assignment_id: "", role: "", since: ""
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.GroupSummary do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Group

  property(:id, source: :group_id)
  property(:name)
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.GroupMembership do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Group

  property(:id, source: :group_id)
  property(:name)
  edge_property(:since)
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.MemberSummary do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Person

  property(:id, source: :person_id)
  property(:name)
  edge_property(:since)
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.RoleAssignment do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Group

  property(:id, source: :group_id)
  edge_property(:assignment_id)
  edge_property(:role)
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.GroupWithMembers do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Group

  property(:id, source: :group_id)
  property(:name)

  relation(:members, Cratis.Chronicle.GraphViewFixtures.MemberOf,
    view: Cratis.Chronicle.GraphViewFixtures.Views.MemberSummary,
    cardinality: :many
  )
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.GroupWithParent do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Group

  property(:id, source: :group_id)
  property(:name)

  relation(:parent, Cratis.Chronicle.GraphViewFixtures.PartOf,
    view: Cratis.Chronicle.GraphViewFixtures.Views.GroupSummary,
    cardinality: :one,
    direction: :outgoing
  )
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.PersonRoles do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Person

  property(:id, source: :person_id)

  relation(:roles, Cratis.Chronicle.GraphViewFixtures.HasRole,
    view: Cratis.Chronicle.GraphViewFixtures.Views.RoleAssignment,
    cardinality: :many
  )
end

defmodule Cratis.Chronicle.GraphViewFixtures.Views.PersonWithGroups do
  use Cratis.Chronicle.Graphs.View, root: Cratis.Chronicle.GraphViewFixtures.Person

  property(:id, source: :person_id)
  property(:name)

  relation(:groups, Cratis.Chronicle.GraphViewFixtures.MemberOf,
    view: Cratis.Chronicle.GraphViewFixtures.Views.GroupMembership,
    cardinality: :many
  )
end

defmodule Cratis.Chronicle.GraphViewFixtures.Organization do
  use Cratis.Chronicle.Graphs.Graph, id: "Organization"

  alias Cratis.Chronicle.GraphViewFixtures.{Group, HasRole, MemberOf, PartOf, Person, Views}

  node Person, key: :person_id do
  end

  node Group, key: :group_id do
  end

  edge MemberOf, source: Person, target: Group do
  end

  edge PartOf, source: Group, target: Group do
  end

  edge HasRole, source: Person, target: Group, identified_by: :assignment_id do
  end

  # Declared in a different order than the names sort, to show the definition sorts them.
  view(Views.PersonWithGroups)
  view(Views.GroupWithMembers)
  view(Views.GroupMembership)
  view(Views.MemberSummary)
  view(Views.GroupWithParent)
  view(Views.GroupSummary)
  view(Views.PersonRoles)
  view(Views.RoleAssignment)
end
