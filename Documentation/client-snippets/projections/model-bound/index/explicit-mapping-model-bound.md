```elixir
defmodule MyApp.ReadModels.IndexExplicitMbAccountInfo do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.IndexExplicitAccountOpened

  defstruct [:name, balance: 0]

  from IndexExplicitAccountOpened,
    set: [name: :name, balance: :initial_balance]
end
```
