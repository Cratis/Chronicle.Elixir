```elixir
defmodule BatchUserRegistered do
  use Chronicle.Events.EventType, id: "batch-user-registered"

  defstruct name: ""
end

defmodule BatchUserRemoved do
  use Chronicle.Events.EventType, id: "batch-user-removed"

  defstruct name: ""
end

defmodule BatchUserEmailChanged do
  use Chronicle.Events.EventType, id: "batch-user-email-changed"

  defstruct email: ""
end

defmodule BatchUsersReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.Observers.EventBatch

  # One call per page, with every BatchUserRegistered and BatchUserRemoved in it.
  @observes BatchUserRegistered
  @observes BatchUserRemoved
  def index(batch, _context) do
    operations =
      Enum.map(batch, fn
        {%BatchUserRegistered{name: name}, context} -> {:upsert, context.event_source_id, name}
        {%BatchUserRemoved{}, context} -> {:delete, context.event_source_id}
      end)

    {failed, throttled} = bulk_index(operations)

    batch = Enum.reduce(failed, batch, &EventBatch.fail(&2, &1, :index_failed))
    Enum.reduce(throttled, batch, &EventBatch.defer(&2, &1, 5_000))
  end

  # A per-event handler for a type no batch function observes.
  @handles BatchUserEmailChanged

  @impl true
  def handle(%BatchUserEmailChanged{}, _context), do: :ok

  # Send the operations to the search index; return the event source ids that failed and the
  # ones the index asked to retry later.
  defp bulk_index(_operations), do: {[], []}
end
```
