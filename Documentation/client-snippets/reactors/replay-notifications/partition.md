```elixir
defmodule MyApp.Events.PartitionNotifiedOrderPlaced do
  use Chronicle.Events.EventType, id: "partition-notified-order-placed"

  defstruct [:order_id]
end

defmodule MyApp.Reactors.PartitionNotifiedOrderReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.PartitionNotifiedOrderPlaced

  @handles PartitionNotifiedOrderPlaced

  @impl true
  def handle(%PartitionNotifiedOrderPlaced{}, _context), do: :ok

  # The partition is the event source id being replayed.
  @impl true
  def on_partition_replay_begin(_partition), do: :ok

  @impl true
  def on_partition_replay_end(_partition), do: :ok
end
```
