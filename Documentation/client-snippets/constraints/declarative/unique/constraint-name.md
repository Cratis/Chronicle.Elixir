```elixir
defmodule MyApp.Events.ConstraintsUniqueNamedUserRegistered do
  use Chronicle.Events.EventType, id: "constraints-unique-named-user-registered"

  unique :email, name: "UniqueEmail"

  defstruct email: ""
end
```
