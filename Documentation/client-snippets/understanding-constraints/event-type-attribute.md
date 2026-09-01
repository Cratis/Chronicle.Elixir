```elixir
defmodule MyApp.Events.UcUserRegisteredOnce do
  use Chronicle.Events.EventType, id: "uc-user-registered-once"

  defstruct [:email, :display_name]

  unique_event_type()
end
```
