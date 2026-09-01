```elixir
defmodule MyApp.Events.UcDedicatedUserRegistered do
  use Chronicle.Events.EventType, id: "uc-dedicated-user-registered"

  defstruct [:email, :display_name]

  unique(:email,
    name: "UcDedicatedUniqueEmail",
    ignore_casing: true,
    message: "That email address is already in use."
  )
end

defmodule MyApp.Events.UcDedicatedUserEmailChanged do
  use Chronicle.Events.EventType, id: "uc-dedicated-user-email-changed"

  defstruct [:new_email]

  unique(:new_email,
    name: "UcDedicatedUniqueEmail",
    ignore_casing: true,
    message: "That email address is already in use."
  )
end

defmodule MyApp.Events.UcDedicatedUserRemoved do
  use Chronicle.Events.EventType, id: "uc-dedicated-user-removed"

  defstruct []

  remove_constraint("UcDedicatedUniqueEmail")
end
```
