```elixir
defmodule MyApp.Events.ConstraintsUniqueCasingUserRegistered do
  use Chronicle.Events.EventType, id: "constraints-unique-casing-user-registered"

  unique :email, ignore_casing: true

  defstruct email: ""
end
```
