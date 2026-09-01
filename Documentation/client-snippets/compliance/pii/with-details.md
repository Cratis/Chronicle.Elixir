```elixir
defmodule MyApp.Compliance.Pii.PersonNameWithDetails do
  use Chronicle.Concept, type: :string
  pii("Collected under GDPR Art. 6(1)(b) — necessary for contract performance")
end
```
