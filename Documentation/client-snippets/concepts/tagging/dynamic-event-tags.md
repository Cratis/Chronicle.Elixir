```elixir
defmodule MyApp.Events.TaggingUserLoggedIn do
  use Chronicle.Events.EventType, id: "tagging-user-logged-in"

  defstruct [:user_id, :logged_in_at]
end

defmodule MyApp.TaggingUserLoginService do
  alias MyApp.Events.TaggingUserLoggedIn

  def record_login(event_source_id, user_id) do
    # This event type declares no static tags, so the event carries only the two
    # dynamic tags: ["production", "critical"]
    Chronicle.append(
      event_source_id,
      %TaggingUserLoggedIn{user_id: user_id, logged_in_at: DateTime.utc_now()},
      tags: ["production", "critical"]
    )
  end
end
```
