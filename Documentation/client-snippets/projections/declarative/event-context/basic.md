```elixir title="Mapping event context properties"
defmodule MyApp.Projections.DecEventContextUserActivityProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecEventContextUserActivity

  alias MyApp.Events.{DecEventContextUserLoggedIn, DecEventContextUserPerformedAction}

  from DecEventContextUserLoggedIn,
    set: [
      user_id: :event_source_id,
      last_login: :occurred
    ]

  from DecEventContextUserPerformedAction,
    set: [
      user_id: :event_source_id,
      last_activity: :occurred
    ]
end
```
