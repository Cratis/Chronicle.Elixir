```elixir
defmodule MyApp.Events.CopyPersonalDetailsRecorded do
  use Chronicle.Events.EventType, id: "copy-personal-details-recorded"

  defstruct [:name, :social_security_number]
end

defmodule MyApp.Events.CopyAddressChanged do
  use Chronicle.Events.EventType, id: "copy-address-changed"

  defstruct [:street, :city]
end

defmodule MyApp.CopyByEventSourceAndTypesService do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{CopyAddressChanged, CopyPersonalDetailsRecorded}

  def copy_personal_data(source_id, target_id) do
    {:ok, job_id} =
      EventLog.copy(source_id, target_id, [CopyPersonalDetailsRecorded, CopyAddressChanged])

    job_id
  end
end
```
