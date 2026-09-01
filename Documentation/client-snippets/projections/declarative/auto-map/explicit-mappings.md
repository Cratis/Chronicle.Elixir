```elixir title="AutoMap with explicit mappings"
defmodule MyApp.Events.AutoMapAccountOpened do
  use Chronicle.Events.EventType, id: "auto-map-account-opened"

  defstruct [:name, :email]
end

defmodule MyApp.Events.AutoMapAccountEmailChanged do
  use Chronicle.Events.EventType, id: "auto-map-account-email-changed"

  defstruct [:email]
end

defmodule MyApp.ReadModels.AutoMapAccount do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :status, :created_at]
end

defmodule MyApp.Projections.AutoMapAccountProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AutoMapAccount

  alias MyApp.Events.{AutoMapAccountEmailChanged, AutoMapAccountOpened}

  # `name` and `email` are mapped automatically by AutoMap; only the
  # exceptions below need an explicit set:.
  from AutoMapAccountOpened,
    set: [
      status: "$value(Active)",
      created_at: :occurred
    ]

  # Uses AutoMap for `email` — no set: list needed.
  from AutoMapAccountEmailChanged
end
```
