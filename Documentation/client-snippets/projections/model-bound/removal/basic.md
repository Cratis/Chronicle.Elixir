```elixir
defmodule MyApp.Events.RemovalAccountOpened do
  use Chronicle.Events.EventType, id: "removal-account-opened-v1"

  defstruct [:name, :balance]
end

defmodule MyApp.Events.RemovalAccountClosed do
  use Chronicle.Events.EventType, id: "removal-account-closed-v1"

  defstruct []
end

defmodule MyApp.ReadModels.RemovalAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{RemovalAccountOpened, RemovalAccountClosed}

  defstruct [:id, :name, :balance]

  from RemovalAccountOpened,
    set: [id: :event_source_id, name: :name, balance: :balance]

  removed_with RemovalAccountClosed
end
```
