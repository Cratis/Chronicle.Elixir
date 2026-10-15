```elixir
defmodule MyApp.Events.UniqueUsernameUserRegistered do
  use Chronicle.Events.EventType, id: "unique-username-user-registered"

  defstruct [:username, :email]

  unique(:username)
end

defmodule MyApp.UniqueUsernameRegistration do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.UniqueUsernameUserRegistered

  def register(user_id, username, email) do
    event = %UniqueUsernameUserRegistered{username: username, email: email}

    case EventLog.append_with_result(user_id, event) do
      {:ok, _result} ->
        nil

      # The kernel rejected the append, so this holds for every writer, not only this one.
      {:error, %{constraint_violations: [first | _]}} ->
        first.message

      {:error, _result} ->
        "The user could not be registered."
    end
  end
end
```
