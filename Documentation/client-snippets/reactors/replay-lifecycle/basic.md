```elixir
defmodule MyApp.Reactors.ReplayAwareNotifier do
  use Chronicle.Reactors.Reactor

  require Logger

  alias MyApp.Events.OrderPlaced

  @handles OrderPlaced

  @impl true
  def handle(%OrderPlaced{}, _context), do: :ok

  @impl true
  def on_replay_begin, do: Logger.info("Replay starting")

  @impl true
  def on_replay_end, do: Logger.info("Replay finished")
end
```
