```elixir
defmodule MyApp.Compliance.Pii.PersonName do
  use Cratis.Chronicle.Concept, type: :string
  pii()
end
```
