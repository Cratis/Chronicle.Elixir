```elixir
defmodule MyApp.Concepts.ConstraintsModelBoundUniqueEmailAddress do
  use Chronicle.Concept, type: :string
end

defmodule MyApp.Events.ConstraintsModelBoundUniqueAuthorRegistered do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-author-registered"

  unique :email, name: "UniqueAuthorEmail"

  defstruct email: %MyApp.Concepts.ConstraintsModelBoundUniqueEmailAddress{}
end
```
