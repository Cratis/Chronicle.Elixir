```elixir
defmodule MyApp.Events.MbRemovalMultipleAccountOpened do
  use Chronicle.Events.EventType, id: "mb-removal-multiple-account-opened"

  defstruct [:name]
end

defmodule MyApp.Events.MbRemovalMultipleAccountClosed do
  use Chronicle.Events.EventType, id: "mb-removal-multiple-account-closed"

  defstruct []
end

defmodule MyApp.Events.MbRemovalMultipleAccountMerged do
  use Chronicle.Events.EventType, id: "mb-removal-multiple-account-merged"

  defstruct [:source_account_id]
end

defmodule MyApp.ReadModels.MbRemovalMultipleAccount do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, name: nil

  from MyApp.Events.MbRemovalMultipleAccountOpened,
    set: [id: :event_source_id, name: :name]

  removed_with MyApp.Events.MbRemovalMultipleAccountClosed, []

  # The merged event is raised on the surviving account; its `source_account_id` names the
  # account that is removed.
  removed_with MyApp.Events.MbRemovalMultipleAccountMerged, key: :source_account_id
end
```
