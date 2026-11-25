```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueSeveralInvitationAccepted do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-several-invitation-accepted"

  defstruct []

  remove_constraint("UniqueInvitedEmail")
end

defmodule MyApp.Events.ConstraintsModelBoundUniqueSeveralInvitationRevoked do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-several-invitation-revoked"

  defstruct []

  remove_constraint("UniqueInvitedEmail")
end

defmodule MyApp.Events.ConstraintsModelBoundUniqueSeveralInvitationExpired do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-several-invitation-expired"

  defstruct []

  remove_constraint("UniqueInvitedEmail")
end
```
