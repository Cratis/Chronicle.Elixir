```elixir title="Partial event shapes"
defmodule MyApp.Events.ConventionPartialUserRegistered do
  use Chronicle.Events.EventType, id: "convention-partial-user-registered-v1"

  defstruct [:email]
end

defmodule MyApp.Events.ConventionPartialUserCompleted do
  use Chronicle.Events.EventType, id: "convention-partial-user-completed-v1"

  defstruct [:first_name, :last_name, :phone]
end

defmodule MyApp.ReadModels.ConventionPartialUser do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{ConventionPartialUserRegistered, ConventionPartialUserCompleted}

  defstruct [:email, :first_name, :last_name, :phone]

  from ConventionPartialUserRegistered
  from ConventionPartialUserCompleted
end
```
