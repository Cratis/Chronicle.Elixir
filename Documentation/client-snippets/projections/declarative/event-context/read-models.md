```elixir title="Read models"
defmodule MyApp.ReadModels.DecEventContextUserActivity do
  use Chronicle.ReadModels.ReadModel

  defstruct [:user_id, :last_login, :last_activity]
end

defmodule MyApp.ReadModels.DecEventContextAuditEntry do
  use Chronicle.ReadModels.ReadModel

  defstruct [:event_id, :occurred_at, :correlation_id, :action_type, :user_id]
end
```
