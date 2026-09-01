```elixir
defmodule MyApp.Events.ConcurrencyStrategyAccountNameChanged do
  use Chronicle.Events.EventType, id: "concurrency-strategy-account-name-changed"

  defstruct [:new_name]
end

defmodule MyApp.ConcurrencyOptimisticAccountService do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyStrategyAccountNameChanged

  def update_account(account_id, new_name) do
    # The optimistic strategy: read the current tail for this event source and
    # expect nothing to have been appended since.
    {:ok, tail} = EventLog.get_tail_sequence_number(account_id)
    scope = ConcurrencyScope.for_event_source(tail)

    Chronicle.append(
      account_id,
      %ConcurrencyStrategyAccountNameChanged{new_name: new_name},
      concurrency_scope: scope
    )
  end
end
```
