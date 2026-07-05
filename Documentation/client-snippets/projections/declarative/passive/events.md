```elixir title="Events"
defmodule MyApp.Events.DecPassiveUserCreated do
  use Chronicle.Events.EventType, id: "dec-passive-user-created"

  defstruct [:name, :email]
end

defmodule MyApp.Events.DecPassiveUserUpdated do
  use Chronicle.Events.EventType, id: "dec-passive-user-updated"

  defstruct [:name, :email]
end

defmodule MyApp.Events.DecPassiveUserLoggedIn do
  use Chronicle.Events.EventType, id: "dec-passive-user-logged-in"

  defstruct [:login_time]
end
```
