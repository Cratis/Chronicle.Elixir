```elixir
defmodule MyApp.Events.IndexAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "index-account-opened-v1"

  defstruct [:name, :initial_balance]
end

defmodule MyApp.ReadModels.IndexAccountInfo do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.IndexAccountOpened

  defstruct [:id, :name, balance: 0]

  from IndexAccountOpened,
    set: [id: :event_source_id, name: :name, balance: :initial_balance]
end
```
