```elixir
defmodule MyApp.Events.ReplayLifecycleOrderPlaced do
  use Chronicle.Events.EventType, id: "replay-lifecycle-order-placed"

  defstruct [:order_id]
end

defmodule MyApp.Reactors.ReplayAwareNotifier do
  use Chronicle.Reactors.Reactor

  require Logger

  alias MyApp.Events.ReplayLifecycleOrderPlaced

  @handles ReplayLifecycleOrderPlaced

  @impl true
  def handle(%ReplayLifecycleOrderPlaced{}, _context), do: :ok

  @impl true
  def on_replay_begin, do: Logger.info("Replay starting")

  @impl true
  def on_replay_end, do: Logger.info("Replay finished")
end
```
