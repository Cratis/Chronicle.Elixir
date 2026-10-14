```elixir title="Composite key from event content and context"
defmodule MyApp.Projections.AuditEntryProjectionWithCompositeKey do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AuditEntryWithCompositeKey

  alias MyApp.Events.CompositeUserAction

  from CompositeUserAction,
    key:
      {:composite,
       [
         user_id: :user_id,
         timestamp: {:event_context, "Occurred"}
       ]}
end
```
