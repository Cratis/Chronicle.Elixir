```elixir title="Declarative from_every"
defmodule MyApp.Events.UserCreatedDeclarativeEvery do
  use Chronicle.Events.EventType, id: "user-created-declarative-every-v1"

  defstruct [:name, :email]
end

defmodule MyApp.Events.UserEmailChangedDeclarativeEvery do
  use Chronicle.Events.EventType, id: "user-email-changed-declarative-every-v1"

  defstruct [:email]
end

defmodule MyApp.ReadModels.UserProfileDeclarativeEvery do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :last_updated]
end

defmodule MyApp.Projections.UserProfileDeclarativeEveryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.UserProfileDeclarativeEvery

  alias MyApp.Events.{UserCreatedDeclarativeEvery, UserEmailChangedDeclarativeEvery}

  from UserCreatedDeclarativeEvery,
    set: [
      name: :name,
      email: :email
    ]

  from UserEmailChangedDeclarativeEvery,
    set: [email: :email]

  from_every set: [last_updated: :occurred]
end
```
