```elixir
defmodule MyApp.Events.ReactorsIndexEmailConfirmed do
  use Chronicle.Events.EventType, id: "reactors-index-email-confirmed"

  defstruct [:email]
end

defmodule MyApp.Reactors.ReactorsIndexEmailNotificationsReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ReactorsIndexEmailConfirmed

  @handles ReactorsIndexEmailConfirmed

  @impl true
  def handle(%ReactorsIndexEmailConfirmed{} = event, context) do
    send_confirmation(event.email, Map.get(context, :occurred))

    :ok
  end

  defp send_confirmation(_email, _occurred), do: :ok
end
```
