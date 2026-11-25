```elixir
defmodule MyApp.CorrelationIdentityCausationRenamingAnIdentity do
  alias Cratis.Chronicle.Identities

  def rename do
    Identities.rename("subject-42", "Jane Austen")
  end
end
```
