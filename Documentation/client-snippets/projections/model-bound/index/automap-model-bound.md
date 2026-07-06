```elixir
defmodule MyApp.ReadModels.IndexAutoMapMbAccountInfo do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.IndexAutoMapAccountOpened

  # `name` and `balance` are mapped automatically from the matching event
  # fields — no `set:` list needed.
  defstruct [:name, balance: 0]

  from IndexAutoMapAccountOpened
end
```
