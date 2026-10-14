```elixir
defmodule MyApp.Events.MbJoinsChildrenMemberAdded do
  use Chronicle.Events.EventType, id: "mb-joins-children-member-added"

  defstruct [:member_id]
end

defmodule MyApp.Events.MbJoinsChildrenMemberProfileUpdated do
  use Chronicle.Events.EventType, id: "mb-joins-children-member-profile-updated"

  defstruct [:member_id, :display_name]
end

defmodule MyApp.ReadModels.MbJoinsChildrenMember do
  defstruct member_id: nil, display_name: nil
end

defmodule MyApp.ReadModels.MbJoinsChildrenTeam do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.MbJoinsChildrenMember}]

  defstruct team_id: nil, members: []

  children :members, identified_by: :member_id do
    from MyApp.Events.MbJoinsChildrenMemberAdded, key: :member_id, set: [member_id: :member_id]

    # A join inside `children` does not take `:on` — it always matches by the collection's
    # `identified_by`, so the member who profile changed is found by `member_id` automatically.
    join MyApp.Events.MbJoinsChildrenMemberProfileUpdated,
      key: :member_id,
      set: [display_name: :display_name]
  end
end
```
