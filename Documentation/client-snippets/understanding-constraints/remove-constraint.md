```elixir
defmodule MyApp.Events.UcUserRemoved do
  use Chronicle.Events.EventType, id: "uc-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueEmail")
end
```
