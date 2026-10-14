```elixir
defmodule MyApp.Events.InvitationSent do
  use Chronicle.Events.EventType, id: "troubleshooting-invitation-sent"

  defstruct [:email]
end

defmodule MyApp.Reactors.InvitationMailReactor do
  use Chronicle.Reactors.Reactor

  @handles MyApp.Events.InvitationSent

  @impl true
  def handle(%MyApp.Events.InvitationSent{}, _context), do: :ok
end

defmodule MyApp.Troubleshooting.RetryReactorPartition do
  alias MyApp.Reactors.InvitationMailReactor

  def retry do
    observer_id = InvitationMailReactor.__chronicle_reactor__(:id)
    {:ok, failed_partitions} = Chronicle.FailedPartitions.get_for(observer_id)

    case failed_partitions do
      [failed_partition | _] ->
        {:ok, outcome} =
          Chronicle.Observers.retry_partition(InvitationMailReactor, failed_partition.partition)

        # Handle outcome before reporting recovery as successful.
        outcome

      [] ->
        :nothing_failed
    end
  end
end
```

In Elixir, `{:ok, :started}` means a recovery job started or resumed. `{:ok, :partition_not_found}` means the failure was already cleared (or never existed), not that the call failed. `{:ok, :observer_quarantined}` and `{:ok, :partition_quarantined}` mean retry was refused until the corresponding quarantine is cleared. `{:ok, :unknown}` means the server returned an outcome this client version does not recognize; do not treat it as success.
