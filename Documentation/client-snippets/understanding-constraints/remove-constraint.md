```elixir
defmodule MyApp.Events.UcUserRemoved do
  use Cratis.Chronicle.Events.EventType, id: "uc-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueEmail")
end
```
