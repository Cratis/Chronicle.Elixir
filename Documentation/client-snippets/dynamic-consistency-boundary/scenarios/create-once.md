```elixir
defmodule MyApp.Events.CreateOnceAccountOpened do
  use Chronicle.Events.EventType, id: "create-once-account-opened"

  defstruct [:owner]

  # At most one AccountOpened is ever appended for the same event source.
  unique_event_type()
end
```
