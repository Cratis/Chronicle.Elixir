```elixir
defmodule MyApp.Events.PdlAutoMapUserRegistered do
  use Chronicle.Events.EventType, id: "pdl-auto-map-user-registered"

  defstruct [:name, :email, :age]
end
```
