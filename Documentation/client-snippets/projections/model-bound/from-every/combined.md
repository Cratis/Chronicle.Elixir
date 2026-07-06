```elixir title="Combine specific mappings with every-event metadata"
defmodule MyApp.Events.UserRegisteredForEvery do
  use Chronicle.Events.EventType, id: "user-registered-for-every-v1"

  defstruct [:name, :email]
end

defmodule MyApp.Events.UserNameChangedForEvery do
  use Chronicle.Events.EventType, id: "user-name-changed-for-every-v1"

  defstruct [:new_name]
end

defmodule MyApp.Events.UserEmailChangedForEvery do
  use Chronicle.Events.EventType, id: "user-email-changed-for-every-v1"

  defstruct [:new_email]
end

defmodule MyApp.ReadModels.UserProfileFromEvery do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{UserEmailChangedForEvery, UserNameChangedForEvery, UserRegisteredForEvery}

  defstruct [:id, :name, :email, :last_updated]

  from UserRegisteredForEvery,
    set: [
      id: :event_source_id,
      name: :name,
      email: :email
    ]

  from UserNameChangedForEvery,
    set: [name: :new_name]

  from UserEmailChangedForEvery,
    set: [email: :new_email]

  from_every set: [last_updated: :occurred]
end
```
