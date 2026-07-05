```elixir
defmodule MyApp.Events.PdlAutoMapUserRegistered do
  use Chronicle.Events.EventType

  defstruct [:name, :email, :age]
end
```
