```elixir title="Model-bound set mapping"
defmodule MyApp.Events.UserRegisteredForContact do
  use Chronicle.Events.EventType, id: "user-registered-for-contact-v1"

  defstruct [:name, :email]
end

defmodule MyApp.ReadModels.UserContact do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.UserRegisteredForContact

  defstruct [:id, :name, :email]

  from UserRegisteredForContact,
    set: [
      id: :event_source_id,
      email: :email,
      name: :name
    ]
end
```
