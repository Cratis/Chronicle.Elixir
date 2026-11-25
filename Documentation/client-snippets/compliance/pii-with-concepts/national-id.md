```elixir
defmodule MyApp.Compliance.PiiWithConcepts.NationalIdNumber do
  use Cratis.Chronicle.Concept, type: :string
  pii("National ID number — sensitive personal identifier")
end
```
