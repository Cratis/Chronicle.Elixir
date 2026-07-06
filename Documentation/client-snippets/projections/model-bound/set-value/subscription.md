```elixir
defmodule MyApp.Events.SetValueSubscriptionStarted do
  use Chronicle.Events.EventType, id: "set-value-subscription-started-v1"

  defstruct []
end

defmodule MyApp.Events.SetValueSubscriptionPaused do
  use Chronicle.Events.EventType, id: "set-value-subscription-paused-v1"

  defstruct []
end

defmodule MyApp.Events.SetValueSubscriptionCanceled do
  use Chronicle.Events.EventType, id: "set-value-subscription-canceled-v1"

  defstruct []
end

defmodule MyApp.ReadModels.SetValueSubscription do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    SetValueSubscriptionStarted,
    SetValueSubscriptionPaused,
    SetValueSubscriptionCanceled
  }

  defstruct [:id, state: ""]

  from SetValueSubscriptionStarted,
    set: [id: :event_source_id, state: "$value(active)"]

  from SetValueSubscriptionPaused,
    set: [state: "$value(paused)"]

  from SetValueSubscriptionCanceled,
    set: [state: "$value(canceled)"]
end
```
