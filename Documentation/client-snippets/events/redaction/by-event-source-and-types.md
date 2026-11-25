```elixir
defmodule MyApp.Events.RedactionPersonalDetailsRecorded do
  use Cratis.Chronicle.Events.EventType, id: "redaction-personal-details-recorded"

  defstruct [:name, :social_security_number]
end

defmodule MyApp.Events.RedactionAddressChanged do
  use Cratis.Chronicle.Events.EventType, id: "redaction-address-changed"

  defstruct [:street, :city]
end

defmodule MyApp.RedactionByEventSourceAndTypesService do
  alias Cratis.Chronicle.EventSequences.EventLog
  alias MyApp.Events.{RedactionAddressChanged, RedactionPersonalDetailsRecorded}

  def redact_personal_data(event_source_id) do
    EventLog.redact_for_event_source(event_source_id, "PII erasure", [
      RedactionPersonalDetailsRecorded,
      RedactionAddressChanged
    ])
  end
end
```
