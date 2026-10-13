```elixir
defmodule MyApp.Events.DecJoinsChildMemberAssignedToProject do
  use Chronicle.Events.EventType, id: "dec-joins-child-member-assigned-to-project"

  defstruct [:project_id, :member_id]
end

defmodule MyApp.Events.DecJoinsChildMemberRegistered do
  use Chronicle.Events.EventType, id: "dec-joins-child-member-registered"

  defstruct [:name]
end

defmodule MyApp.ReadModels.DecJoinsChildProjectMember do
  use Chronicle.ReadModels.ReadModel

  defstruct member_id: nil, name: nil
end

defmodule MyApp.ReadModels.DecJoinsChildProjectBoard do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.DecJoinsChildProjectMember}]

  defstruct members: []
end

defmodule MyApp.Projections.DecJoinsChildProjectBoardProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecJoinsChildProjectBoard

  children :members, identified_by: :member_id do
    from MyApp.Events.DecJoinsChildMemberAssignedToProject,
      parent_key: :project_id,
      key: :member_id,
      set: [member_id: :member_id]

    join MyApp.Events.DecJoinsChildMemberRegistered,
      on: :member_id,
      set: [name: :name]
  end
end
```
