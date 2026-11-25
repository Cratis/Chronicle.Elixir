```elixir
defmodule MyApp.Compliance.Pii.LegalName do
  use Cratis.Chronicle.Concept, type: :string
  pii("Full legal name — required for contract identification")
end
```
