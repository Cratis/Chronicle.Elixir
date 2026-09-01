```elixir
defmodule MyApp.Events.UcUserRegistered do
  use Chronicle.Events.EventType, id: "uc-user-registered"

  defstruct [:email, :display_name]

  unique(:email, name: "UniqueEmail")
end
```
