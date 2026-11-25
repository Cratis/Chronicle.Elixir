```elixir
defmodule MyApp.Concepts.ConstraintsModelBoundUniqueEmailAddress do
  use Cratis.Chronicle.Concept, type: :string
end

defmodule MyApp.Events.ConstraintsModelBoundUniqueAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-author-registered"

  unique :email, name: "UniqueAuthorEmail"

  defstruct email: %MyApp.Concepts.ConstraintsModelBoundUniqueEmailAddress{}
end
```
