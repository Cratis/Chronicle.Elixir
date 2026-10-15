```elixir
defmodule MyApp.Events.ReplayNotifiedOrderPlaced do
  use Chronicle.Events.EventType, id: "replay-notified-order-placed"

  defstruct [:order_id]
end

# The notifications run outside the reactor's event handling, so anything they share lives in
# a process of its own that you start under your supervision tree.
defmodule MyApp.ReplayNotificationGate do
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> :open end, name: __MODULE__)

  def pause, do: Agent.update(__MODULE__, fn _ -> :paused end)
  def resume, do: Agent.update(__MODULE__, fn _ -> :open end)
  def open?, do: Agent.get(__MODULE__, &(&1 == :open))
end

defmodule MyApp.Reactors.ReplayNotifiedOrderReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ReplayNotifiedOrderPlaced
  alias MyApp.ReplayNotificationGate

  @handles ReplayNotifiedOrderPlaced

  # Handles the event both live and during the replay.
  @impl true
  def handle(%ReplayNotifiedOrderPlaced{}, _context), do: :ok

  @impl true
  def on_replay_begin, do: ReplayNotificationGate.pause()

  @impl true
  def on_replay_end, do: ReplayNotificationGate.resume()
end
```
