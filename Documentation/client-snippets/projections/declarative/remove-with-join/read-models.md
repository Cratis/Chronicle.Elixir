```elixir title="Read models"
defmodule MyApp.ReadModels.DecRwjGroupMembership do
  defstruct group_id: nil
end

defmodule MyApp.ReadModels.DecRwjUserWithGroups do
  use Chronicle.ReadModels.ReadModel,
    types: [groups: {:list, MyApp.ReadModels.DecRwjGroupMembership}]

  defstruct user_id: nil, groups: []
end

defmodule MyApp.ReadModels.DecRwjUserWithGroupsExplicitKey do
  use Chronicle.ReadModels.ReadModel,
    types: [groups: {:list, MyApp.ReadModels.DecRwjGroupMembership}]

  defstruct user_id: nil, groups: []
end
```
