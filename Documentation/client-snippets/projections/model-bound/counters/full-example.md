```elixir
defmodule MyApp.Events.CountersUserLoggedInFull do
  use Chronicle.Events.EventType, id: "counters-user-logged-in-full-v1"

  defstruct [:timestamp]
end

defmodule MyApp.Events.CountersUserLoggedOutFull do
  use Chronicle.Events.EventType, id: "counters-user-logged-out-full-v1"

  defstruct [:timestamp]
end

defmodule MyApp.Events.CountersPurchaseMade do
  use Chronicle.Events.EventType, id: "counters-purchase-made-v1"

  defstruct [:amount]
end

defmodule MyApp.Events.CountersRefundIssued do
  use Chronicle.Events.EventType, id: "counters-refund-issued-v1"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.CountersUserActivity do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    CountersUserLoggedInFull,
    CountersUserLoggedOutFull,
    CountersPurchaseMade,
    CountersRefundIssued
  }

  defstruct [
    :user_id,
    total_logins: 0,
    total_logouts: 0,
    active_sessions: 0,
    purchase_count: 0,
    refund_count: 0,
    net_spent: 0
  ]

  # Track login/logout counts and active sessions
  from CountersUserLoggedInFull,
    set: [user_id: :event_source_id],
    count: :total_logins,
    add: [active_sessions: 1]

  from CountersUserLoggedOutFull,
    count: :total_logouts,
    subtract: [active_sessions: 1]

  # Track transaction counts and net value
  from CountersPurchaseMade,
    count: :purchase_count,
    add: [net_spent: :amount]

  from CountersRefundIssued,
    count: :refund_count,
    subtract: [net_spent: :amount]
end
```
