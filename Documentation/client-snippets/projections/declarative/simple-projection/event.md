```elixir
defmodule MyApp.Events.DecSimpleUserCreated do
  use Cratis.Chronicle.Events.EventType, id: "dec-simple-user-created"

  defstruct [:name, :email, :created_at]
end
```
