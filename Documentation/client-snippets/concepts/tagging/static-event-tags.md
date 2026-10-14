```elixir
defmodule MyApp.Events.TaggingStaticUserLoggedIn do
  use Chronicle.Events.EventType,
    id: "tagging-static-user-logged-in",
    tags: ["analytics", "user-action"]

  defstruct [:user_id, :logged_in_at]
end

# There is one `tags:` option: list every tag the event type carries in it.
defmodule MyApp.Events.TaggingStaticUserPasswordChanged do
  use Chronicle.Events.EventType,
    id: "tagging-static-user-password-changed",
    tags: ["security", "audit"]

  defstruct [:user_id, :changed_at]
end
```
