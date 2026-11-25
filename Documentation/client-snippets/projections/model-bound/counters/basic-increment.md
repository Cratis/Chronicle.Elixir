```elixir
defmodule MyApp.Events.CountersUserLoggedIn do
  use Cratis.Chronicle.Events.EventType, id: "counters-user-logged-in-v1"

  defstruct []
end

defmodule MyApp.ReadModels.CountersUserStatistics do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.CountersUserLoggedIn

  defstruct [:user_id, login_count: 0]

  from CountersUserLoggedIn,
    set: [user_id: :event_source_id],
    add: [login_count: 1]
end
```
