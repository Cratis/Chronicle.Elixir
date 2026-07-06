```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueUserRegistered do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-user-registered"

  defstruct [:email, :display_name]

  unique(:email, name: "UniqueEmail")
end

defmodule MyApp.Events.ConstraintsModelBoundUniqueUserEmailChanged do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-user-email-changed"

  defstruct [:new_email]

  unique(:new_email, name: "UniqueEmail")
end
```
