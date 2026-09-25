```elixir
defmodule MyApp.Events.ConcurrencyAccountValidated do
  use Chronicle.Events.EventType, id: "concurrency-batch-account-validated"

  defstruct []
end

defmodule MyApp.Events.ConcurrencyAccountProcessed do
  use Chronicle.Events.EventType, id: "concurrency-batch-account-processed"

  defstruct []
end

defmodule MyApp.ConcurrencyBatchAccountProcessor do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.{ConcurrencyAccountProcessed, ConcurrencyAccountValidated}

  def process_account_batch(account_id) do
    scope =
      ConcurrencyScope.for_event_source(30,
        event_types: [ConcurrencyAccountProcessed, ConcurrencyAccountValidated]
      )

    Chronicle.append_many(
      account_id,
      [%ConcurrencyAccountValidated{}, %ConcurrencyAccountProcessed{}],
      concurrency_scope: scope
    )
  end
end
```
