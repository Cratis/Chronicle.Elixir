```elixir
defmodule MyApp.Events.RemovalWithKeyAccountOpened do
  use Chronicle.Events.EventType, id: "removal-with-key-account-opened-v1"

  defstruct [:name]
end

defmodule MyApp.Events.RemovalWithKeyAccountClosed do
  use Chronicle.Events.EventType, id: "removal-with-key-account-closed-v1"

  defstruct [:account_id]
end

defmodule MyApp.ReadModels.RemovalWithKeyAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{RemovalWithKeyAccountOpened, RemovalWithKeyAccountClosed}

  defstruct [:id, :name]

  from RemovalWithKeyAccountOpened,
    set: [id: :event_source_id, name: :name]

  removed_with RemovalWithKeyAccountClosed, key: :account_id
end
```
