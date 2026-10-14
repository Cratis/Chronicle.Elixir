```elixir title="Read model with children"
defmodule MyApp.ReadModels.GroupMember do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupWithMembers do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMember}]

  defstruct name: nil, description: nil, members: []
end
```
