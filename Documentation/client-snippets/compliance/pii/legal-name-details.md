```elixir
defmodule MyApp.Compliance.Pii.LegalName do
  use Chronicle.Concept, type: :string
  pii("Full legal name — required for contract identification")
end
```
