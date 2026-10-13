```elixir
defmodule MyApp.ReadModels.ChoosingStyleBookStatus do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, title: nil, isbn: nil, is_borrowed: false, borrowed_by: nil

  pii :borrowed_by
end
```
