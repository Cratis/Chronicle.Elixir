```elixir
defmodule MyApp.Events.ConcurrencyStrategyAccountNameChanged do
  use Chronicle.Events.EventType, id: "concurrency-strategy-account-name-changed"

  defstruct [:new_name]
end

defmodule MyApp.ConcurrencyOptimisticAccountService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyStrategyAccountNameChanged

  def update_account(account_id, new_name) do
    # The optimistic strategy, as a one-off: read the current tail for this event source
    # and expect nothing to have been appended since. `at_tail/2` reads and builds the scope
    # in one call.
    {:ok, scope} = ConcurrencyScope.at_tail(account_id)

    Chronicle.append(
      account_id,
      %ConcurrencyStrategyAccountNameChanged{new_name: new_name},
      concurrency_scope: scope
    )
  end
end
```

To apply the optimistic strategy to every append on a client by default instead of building the
scope per call, configure `Chronicle.Client`:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  concurrency: [default: :optimistic]}
```

An append that already carries an explicit or definition-derived scope is left alone; the default
strategy only fills in the ones that have neither.
