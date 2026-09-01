```elixir
defmodule MyApp.CorrelationIdentityCausationRenamingAnIdentity do
  alias Chronicle.Identities

  def rename do
    Identities.rename("subject-42", "Jane Austen")
  end
end
```
