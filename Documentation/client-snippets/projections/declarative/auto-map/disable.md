```elixir
defmodule MyApp.Events.AutoMapDisabledAccountRegistered do
  use Chronicle.Events.EventType, id: "auto-map-disabled-account-registered"

  defstruct [:account_name, :contact_email]
end

defmodule MyApp.ReadModels.AutoMapDisabledAccount do
  use Chronicle.ReadModels.ReadModel

  defstruct name: nil, email: nil, created_at: nil

  # Nothing is mapped by name - every property has to be stated.
  no_auto_map()

  from MyApp.Events.AutoMapDisabledAccountRegistered,
    set: [
      name: :account_name,
      email: :contact_email,
      created_at: :occurred
    ]
end
```
