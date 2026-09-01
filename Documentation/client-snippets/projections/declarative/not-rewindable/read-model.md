```elixir
defmodule MyApp.ReadModels.DecNotRewindableAuditLogEntry do
  defstruct [
    :user_id,
    :action,
    :details,
    :occurred_at,
    :processed_at,
    :sequence_number
  ]
end
```
