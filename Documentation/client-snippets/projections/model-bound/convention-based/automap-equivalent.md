```elixir title="Model-bound and declarative AutoMap"
defmodule MyApp.Events.ConventionEquivalentUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "convention-equivalent-user-registered-v1"

  defstruct [:name, :email]
end

defmodule MyApp.ReadModels.ConventionEquivalentUser do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, :email]
end

defmodule MyApp.Projections.ConventionEquivalentProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.ConventionEquivalentUser

  alias MyApp.Events.ConventionEquivalentUserRegistered

  # No `set:` list — matching field names are mapped automatically, the same
  # way the model-bound `from` declaration on the read model itself would.
  from ConventionEquivalentUserRegistered
end
```
