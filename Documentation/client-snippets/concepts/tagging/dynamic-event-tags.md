```elixir
defmodule MyApp.Events.TaggingUserLoggedIn do
  use Chronicle.Events.EventType, id: "tagging-user-logged-in"

  defstruct [:user_id, :logged_in_at]
end

defmodule MyApp.TaggingUserLoginService do
  alias MyApp.Events.TaggingUserLoggedIn

  def record_login(event_source_id, user_id) do
    # Elixir doesn't support static tags on the event type, so this event ends up
    # with only the two dynamic tags: ["production", "critical"]
    Chronicle.append(
      event_source_id,
      %TaggingUserLoggedIn{user_id: user_id, logged_in_at: DateTime.utc_now()},
      tags: ["production", "critical"]
    )
  end
end
```
