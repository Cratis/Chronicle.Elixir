```elixir
defmodule MyApp.Compliance.PiiWithConcepts.PersonName do
  use Chronicle.Concept, type: :string
  pii()
end
```
