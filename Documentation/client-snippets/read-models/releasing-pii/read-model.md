```elixir
defmodule MyApp.Events.ReleasingPiiSupportTicketOpened do
  use Chronicle.Events.EventType, id: "releasing-pii-support-ticket-opened"

  defstruct [:customer_id, :requester_name]
end

defmodule MyApp.ReadModels.ReleasingPiiSupportTicket do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :customer_id, :requester_name]

  subject :customer_id
  pii :requester_name
end

defmodule MyApp.Reducers.ReleasingPiiSupportTicketReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.ReleasingPiiSupportTicket

  alias MyApp.Events.ReleasingPiiSupportTicketOpened

  @handles ReleasingPiiSupportTicketOpened

  @impl true
  def reduce(%ReleasingPiiSupportTicketOpened{} = event, _model, context) do
    %MyApp.ReadModels.ReleasingPiiSupportTicket{
      id: context.event_source_id,
      customer_id: event.customer_id,
      requester_name: event.requester_name
    }
  end
end
```
