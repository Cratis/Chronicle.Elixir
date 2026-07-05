```elixir title="Equivalent explicit mappings"
defmodule MyApp.Events.ExplicitConventionUserRegistered do
  use Chronicle.Events.EventType, id: "explicit-convention-user-registered-v1"

  defstruct [:name, :email, :registered_at]
end

defmodule MyApp.ReadModels.ExplicitConventionUser do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ExplicitConventionUserRegistered

  defstruct [:name, :email, :registered_at]

  from ExplicitConventionUserRegistered,
    set: [name: :name, email: :email, registered_at: :registered_at]
end
```
