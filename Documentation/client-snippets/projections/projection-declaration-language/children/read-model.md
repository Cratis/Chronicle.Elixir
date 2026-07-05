```elixir
defmodule MyApp.ReadModels.PdlGroupMember do
  defstruct user_id: "", name: "", role: ""
end

defmodule MyApp.ReadModels.PdlGroupReadModel do
  defstruct name: "", members: []
end
```
