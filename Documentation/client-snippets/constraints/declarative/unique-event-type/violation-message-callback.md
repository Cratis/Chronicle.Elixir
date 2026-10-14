```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeCallbackProjectInitialized do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-callback-project-initialized"
  defstruct []
end

defmodule MyApp.Constraints.ConstraintsUniqueEventTypeCallbackMessages do
  def project_already_initialized(violation) do
    "Constraint '#{violation."ConstraintName"}' was violated - the project has already been initialized."
  end
end

defmodule MyApp.Constraints.ConstraintsUniqueEventTypeCallbackProjectInitialization do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsUniqueEventTypeCallbackProjectInitialized,
    name: "ConstraintsUniqueEventTypeCallbackProjectInitialization",
    message:
      {MyApp.Constraints.ConstraintsUniqueEventTypeCallbackMessages,
       :project_already_initialized}
end
```
