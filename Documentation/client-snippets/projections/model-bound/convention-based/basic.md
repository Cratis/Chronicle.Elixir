```elixir title="Convention-based mapping"
defmodule MyApp.Events.ConventionUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "convention-user-registered-v1"

  defstruct [:name, :email, :registered_at]
end

defmodule MyApp.ReadModels.ConventionUser do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ConventionUserRegistered

  defstruct [:name, :email, :registered_at]

  # No `set:` list — matching field names are mapped automatically.
  from ConventionUserRegistered
end
```
