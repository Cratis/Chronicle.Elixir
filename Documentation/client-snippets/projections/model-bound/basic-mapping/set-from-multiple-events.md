```elixir title="Multiple set mappings"
defmodule MyApp.Events.AccountOpenedForRename do
  use Chronicle.Events.EventType, id: "account-opened-for-rename-v1"

  defstruct [:account_name]
end

defmodule MyApp.Events.AccountRenamedForRename do
  use Chronicle.Events.EventType, id: "account-renamed-for-rename-v1"

  defstruct [:new_name]
end

defmodule MyApp.ReadModels.RenameableAccount do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{AccountOpenedForRename, AccountRenamedForRename}

  defstruct [:id, :name]

  from AccountOpenedForRename,
    set: [
      id: :event_source_id,
      name: :account_name
    ]

  from AccountRenamedForRename,
    set: [name: :new_name]
end
```
