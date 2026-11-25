```elixir
defmodule EventProcessingCustomerAction do
  use Cratis.Chronicle.Events.EventType, id: "event-processing-customer-action"

  defstruct [:type, :description]
end

defmodule EventProcessingActivity do
  defstruct [:type, :timestamp, :description]
end

defmodule EventProcessingCustomerActivityLog do
  defstruct activities: []
end

defmodule EventProcessingCustomerActivityLogReducer do
  use Cratis.Chronicle.Reducers.Reducer, model: EventProcessingCustomerActivityLog

  alias EventProcessingCustomerAction
  alias EventProcessingActivity

  @handles EventProcessingCustomerAction

  @impl true
  def reduce(%EventProcessingCustomerAction{} = event, current, context) do
    activities = if current, do: current.activities, else: []

    activity = %EventProcessingActivity{
      type: event.type,
      timestamp: Map.get(context, :occurred),
      description: event.description
    }

    %EventProcessingCustomerActivityLog{activities: activities ++ [activity]}
  end
end
```
