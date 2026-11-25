```elixir
defmodule MyApp.Events.ConstraintsUniqueUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-user-registered"

  unique :email, name: "UniqueEmail"

  defstruct email: ""
end

defmodule MyApp.Events.ConstraintsUniqueUserEmailChanged do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-user-email-changed"

  unique :new_email, name: "UniqueEmail"

  defstruct new_email: ""
end

defmodule MyApp.Events.ConstraintsUniqueUserRemoved do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-user-removed"

  remove_constraint "UniqueEmail"

  defstruct []
end
```
