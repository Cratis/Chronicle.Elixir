```elixir title="Composite audit key and read model"
defmodule MyApp.ReadModels.AuditEntryKey do
  defstruct [:user_id, :timestamp]
end

defmodule MyApp.ReadModels.AuditEntryWithCompositeKey do
  defstruct [:id, :action, :details]
end
```
