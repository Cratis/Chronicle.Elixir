```elixir title="Convention-based set mapping"
defmodule MyApp.Events.UserRegisteredForProfile do
  use Chronicle.Events.EventType, id: "user-registered-for-profile"

  defstruct [:name, :email]
end

defmodule MyApp.ReadModels.UserProfile do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.UserRegisteredForProfile

  defstruct [:id, :name, :email]

  # `name` and `email` are mapped automatically from the matching event
  # fields by convention — only the key/id needs to be told where to come
  # from.
  from UserRegisteredForProfile, set: [id: :event_source_id]
end
```
