```elixir
defmodule MyApp.Compliance.Client.PersonName do
  use Cratis.Chronicle.Concept, type: :string
  pii()
end
```
