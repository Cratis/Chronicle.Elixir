```elixir
defmodule MyApp.Events.DecConstantKeyUserJoined do
  use Cratis.Chronicle.Events.EventType, id: "dec-constant-key-user-joined"

  defstruct [:user_id, :user_name]
end

defmodule MyApp.ReadModels.DecConstantKeyTeamMember do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct user_id: nil, name: nil
end

defmodule MyApp.ReadModels.DecConstantKeyTeam do
  use Cratis.Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.DecConstantKeyTeamMember}]

  defstruct members: []
end

defmodule MyApp.Projections.DecConstantKeyTeamActivityProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecConstantKeyTeam

  children :members, identified_by: :user_id do
    from MyApp.Events.DecConstantKeyUserJoined,
      parent_key: "$value(main-team)",
      set: [user_id: :user_id, name: :user_name]
  end
end
```
