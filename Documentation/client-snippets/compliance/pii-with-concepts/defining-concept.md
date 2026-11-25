```elixir
defmodule MyApp.Compliance.PiiWithConcepts.PersonName do
  use Cratis.Chronicle.Concept, type: :string
  pii()
end
```
