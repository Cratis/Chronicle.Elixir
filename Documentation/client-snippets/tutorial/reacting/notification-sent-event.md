```elixir
defmodule MyApp.Events.WaitlistNotificationSent do
  use Chronicle.Events.EventType, id: "waitlist-notification-sent"

  defstruct []
end
```
