```elixir
defmodule MyApp.Events.DecNotRewindableUserLoginAttempt do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-user-login-attempt"

  defstruct user_id: "", succeeded: false
end

defmodule MyApp.Events.DecNotRewindablePermissionChange do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-permission-change"

  defstruct user_id: "", permission: ""
end

defmodule MyApp.ReadModels.DecNotRewindableSecurityAuditEntry do
  use Chronicle.ReadModels.ReadModel

  defstruct audited_at: nil, sequence_number: 0
end

defmodule MyApp.Projections.DecNotRewindableSecurityAuditProjection do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecNotRewindableSecurityAuditEntry,
    not_rewindable: true

  alias MyApp.Events.{DecNotRewindablePermissionChange, DecNotRewindableUserLoginAttempt}

  from_every set: [audited_at: :occurred, sequence_number: "$eventContext(SequenceNumber)"]

  from DecNotRewindableUserLoginAttempt
  from DecNotRewindablePermissionChange
end
```
