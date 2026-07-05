```elixir title="Multiple convention events"
defmodule MyApp.Events.ConventionUserProfileCreated do
  use Chronicle.Events.EventType, id: "convention-user-profile-created-v1"

  defstruct [:name, :email]
end

defmodule MyApp.Events.ConventionUserProfileUpdated do
  use Chronicle.Events.EventType, id: "convention-user-profile-updated-v1"

  defstruct [:name, :email, :phone]
end

defmodule MyApp.ReadModels.ConventionUserProfile do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{ConventionUserProfileCreated, ConventionUserProfileUpdated}

  defstruct [:name, :email, :phone]

  from ConventionUserProfileCreated
  from ConventionUserProfileUpdated
end
```
