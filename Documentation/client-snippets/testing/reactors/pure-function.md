```elixir
defmodule MyApp.Events.TestingPureVibeCancelled do
  use Chronicle.Events.EventType, id: "testing-pure-function-vibe-cancelled"

  defstruct [:host]
end

defmodule MyApp.Events.TestingPureCreateNotification do
  use Chronicle.Events.EventType, id: "testing-pure-function-create-notification"

  defstruct [:host]
end

# The reactor returns the notification event as a side effect, so its logic is a
# pure function of (event, context) — no call to Chronicle.EventSequences.EventLog
# and no client needed to exercise it.
defmodule MyApp.Reactors.TestingPureCancellationReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{TestingPureCreateNotification, TestingPureVibeCancelled}

  @handles TestingPureVibeCancelled

  @impl true
  def handle(%TestingPureVibeCancelled{host: host}, _context),
    do: {:ok, %TestingPureCreateNotification{host: host}}
end

defmodule MyApp.TestingPureFunctionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.EventContext
  alias MyApp.Events.{TestingPureCreateNotification, TestingPureVibeCancelled}
  alias MyApp.Reactors.TestingPureCancellationReactor

  test "a cancelled vibe requests a notification for the host" do
    event = %TestingPureVibeCancelled{host: "Ada"}
    context = %EventContext{event_source_id: "vibe-1"}

    assert {:ok, %TestingPureCreateNotification{host: "Ada"}} =
             TestingPureCancellationReactor.handle(event, context)
  end
end
```
