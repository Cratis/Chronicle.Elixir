```elixir
defmodule MyApp.Events.EmailChanged do
  use Cratis.Chronicle.Events.EventType, id: "email-changed"

  defstruct [:email]

  unique(:email, scope: :per_event_source_type)
end
```
