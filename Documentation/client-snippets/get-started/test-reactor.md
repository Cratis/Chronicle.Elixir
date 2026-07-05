```elixir title="The reactor - does something when it happens"
defmodule MyApp.Reactors.TestReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestEvent

  @handles TestEvent

  @impl true
  def handle(%TestEvent{} = event, _context) do
    IO.puts("Received event with message: #{event.message}")
    :ok
  end
end
```
