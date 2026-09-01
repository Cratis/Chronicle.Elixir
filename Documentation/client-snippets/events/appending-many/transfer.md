```elixir
defmodule MyApp.Events.TransferMoneyWithdrawn do
  use Chronicle.Events.EventType, id: "transfer-money-withdrawn-v1"

  defstruct [:amount]
end

defmodule MyApp.Events.TransferMoneyDeposited do
  use Chronicle.Events.EventType, id: "transfer-money-deposited-v1"

  defstruct [:amount]
end

defmodule MyApp.TransferService do
  alias Chronicle.EventSequences.{EventForEventSourceId, EventLog}
  alias MyApp.Events.{TransferMoneyDeposited, TransferMoneyWithdrawn}

  # Appends both events atomically in a single append-many, each carrying
  # its own target event source id.
  def transfer(from_account, to_account, amount) do
    events = [
      %EventForEventSourceId{
        event_source_id: from_account,
        event: %TransferMoneyWithdrawn{amount: amount}
      },
      %EventForEventSourceId{
        event_source_id: to_account,
        event: %TransferMoneyDeposited{amount: amount}
      }
    ]

    EventLog.append_many_for_event_sources(events)
  end
end
```
