```elixir
defmodule WelcomeEmailRequested do
  use Chronicle.Events.EventType, id: "welcome-email-requested"

  defstruct [:email]
end

defmodule SendWelcomeEmails do
  # Begin at the tail of the event sequence the first time this reactor is
  # registered, so it never acts on history that predates it.
  use Chronicle.Reactors.Reactor, start_at_tail: true

  @handles WelcomeEmailRequested

  @impl true
  def handle(%WelcomeEmailRequested{}, _context) do
    # Send the email.
    :ok
  end
end
```
