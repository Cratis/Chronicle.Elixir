```elixir
defmodule MyApp.Events.ConstraintsUniqueMessageCallbackProjectCreated do
  use Chronicle.Events.EventType, id: "constraints-unique-message-callback-project-created"
  defstruct name: ""
end

defmodule MyApp.Constraints.ConstraintsUniqueMessageCallbackMessages do
  alias Chronicle.Events.ConstraintViolation

  def project_name_taken(violation) do
    "A project named '#{ConstraintViolation.details(violation)[:property_value]}' already exists."
  end
end

defmodule MyApp.Constraints.ConstraintsUniqueMessageCallbackProjectName do
  use Chronicle.Events.Constraint

  unique name: "ConstraintsUniqueMessageCallbackProjectName",
    message: {MyApp.Constraints.ConstraintsUniqueMessageCallbackMessages, :project_name_taken} do
    on MyApp.Events.ConstraintsUniqueMessageCallbackProjectCreated, [:name]
  end
end
```
