```elixir
defmodule MyApp.Compliance.Pii.PersonName do
  use Chronicle.Concept, type: :string
  pii()
end
```
