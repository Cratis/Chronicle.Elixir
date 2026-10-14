```elixir
defmodule MyApp.Events.ConstraintsUniqueSeveralInvitationSent do
  use Chronicle.Events.EventType, id: "constraints-unique-several-invitation-sent"
  defstruct email_address: ""
end

defmodule MyApp.Events.ConstraintsUniqueSeveralInvitationAccepted do
  use Chronicle.Events.EventType, id: "constraints-unique-several-invitation-accepted"
  defstruct []
end

defmodule MyApp.Events.ConstraintsUniqueSeveralInvitationRevoked do
  use Chronicle.Events.EventType, id: "constraints-unique-several-invitation-revoked"
  defstruct []
end

defmodule MyApp.Events.ConstraintsUniqueSeveralInvitationExpired do
  use Chronicle.Events.EventType, id: "constraints-unique-several-invitation-expired"
  defstruct []
end

defmodule MyApp.Constraints.ConstraintsUniqueSeveralInvitedAddress do
  use Chronicle.Events.Constraint

  unique name: "ConstraintsUniqueSeveralInvitedAddress" do
    on MyApp.Events.ConstraintsUniqueSeveralInvitationSent, [:email_address]
    removed_with MyApp.Events.ConstraintsUniqueSeveralInvitationAccepted
    removed_with MyApp.Events.ConstraintsUniqueSeveralInvitationRevoked
    removed_with MyApp.Events.ConstraintsUniqueSeveralInvitationExpired
  end
end
```
