```elixir title="Initial values"
defmodule MyApp.Events.DecInitialValuesUserCreated do
  use Chronicle.Events.EventType, id: "dec-initial-values-user-created"

  defstruct [:name, :email]
end

defmodule MyApp.ReadModels.DecInitialValuesUserProfile do
  use Chronicle.ReadModels.ReadModel

  # Elixir has no separate WithInitialValues builder call — the struct's own
  # defaults are captured as the projection's initial model state.
  defstruct name: "Unknown user",
            email: "",
            status: "Inactive",
            created_at: ~U[1970-01-01 00:00:00Z],
            last_login: nil,
            login_count: 0,
            is_verified: false
end

defmodule MyApp.Projections.DecInitialValuesUserProfileProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecInitialValuesUserProfile

  alias MyApp.Events.DecInitialValuesUserCreated

  from DecInitialValuesUserCreated,
    set: [
      status: "$value(Active)",
      created_at: :occurred
    ]
end
```
