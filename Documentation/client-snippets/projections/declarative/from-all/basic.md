```elixir title="Declarative FromAll"
defmodule MyApp.Events.UserCreatedDeclarativeAll do
  use Chronicle.Events.EventType, id: "user-created-declarative-all-v1"

  defstruct [:name, :email]
end

defmodule MyApp.Events.UserEmailChangedDeclarativeAll do
  use Chronicle.Events.EventType, id: "user-email-changed-declarative-all-v1"

  defstruct [:email]
end

defmodule MyApp.ReadModels.UserProfileDeclarativeAll do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :last_updated]
end

defmodule MyApp.Projections.UserProfileDeclarativeAllProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.UserProfileDeclarativeAll

  alias MyApp.Events.{UserCreatedDeclarativeAll, UserEmailChangedDeclarativeAll}

  from UserCreatedDeclarativeAll
  from UserEmailChangedDeclarativeAll

  from_every set: [last_updated: :occurred]
end
```
