```elixir
defmodule MyApp.Events.EvtSeedingUserRegistered do
  use Chronicle.Events.EventType, id: "evt-seeding-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Events.EvtSeedingEmailVerified do
  use Chronicle.Events.EventType, id: "evt-seeding-email-verified"

  defstruct [:email]
end

defmodule MyApp.Events.EvtSeedingProfileUpdated do
  use Chronicle.Events.EventType, id: "evt-seeding-profile-updated"

  defstruct [:display_name]
end

defmodule MyApp.Events.EvtSeedingOrderPlaced do
  use Chronicle.Events.EventType, id: "evt-seeding-order-placed"

  defstruct [:user_id, :amount]
end
```
