```elixir
defmodule MyApp.Compliance.PiiWithConcepts.NationalIdNumber do
  use Chronicle.Concept, type: :string
  pii("National ID number — sensitive personal identifier")
end
```
