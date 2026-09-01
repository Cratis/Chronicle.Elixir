```elixir
defmodule MyApp.Events.GettingStateObserverProgressSomethingHappened do
  use Chronicle.Events.EventType, id: "getting-state-observer-progress-something-happened"

  defstruct []
end

defmodule MyApp.Reactors.GettingStateObserverProgressReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.GettingStateObserverProgressSomethingHappened

  @handles GettingStateObserverProgressSomethingHappened

  @impl true
  def handle(%GettingStateObserverProgressSomethingHappened{}, _context), do: :ok
end

defmodule MyApp.GettingStateObserverProgress do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Reactors.GettingStateObserverProgressReactor

  def get_relevant_tail do
    # Uses the reactor's @handles event types to compute the relevant tail.
    EventLog.get_tail_sequence_number_for_observer(GettingStateObserverProgressReactor)
  end
end
```
