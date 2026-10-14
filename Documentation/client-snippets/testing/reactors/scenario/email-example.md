```elixir
defmodule MyApp.Events.TestingReactorScenarioEmailOrderShipped do
  use Chronicle.Events.EventType, id: "email-testing-order-shipped"

  defstruct [:order_id, :carrier]
end

defmodule MyApp.TestingReactorScenarioEmailService do
  @callback send_shipping_confirmation(String.t(), String.t()) :: :ok
end

defmodule MyApp.Reactors.TestingReactorScenarioOrderNotificationReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingReactorScenarioEmailOrderShipped

  @handles TestingReactorScenarioEmailOrderShipped

  @impl true
  def handle(%TestingReactorScenarioEmailOrderShipped{} = event, _context) do
    email_service = Application.fetch_env!(:my_app, :testing_reactor_scenario_email_service)
    email_service.send_shipping_confirmation(event.order_id, event.carrier)
  end
end

defmodule MyApp.TestingReactorScenarioRecordingEmailService do
  @behaviour MyApp.TestingReactorScenarioEmailService

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def sent, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def send_shipping_confirmation(order_id, carrier),
    do: Agent.update(__MODULE__, &[{order_id, carrier} | &1])
end

defmodule MyApp.TestingReactorScenarioEmailExampleTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReactorScenarioEmailOrderShipped],
    reactors: [MyApp.Reactors.TestingReactorScenarioOrderNotificationReactor]

  alias MyApp.Events.TestingReactorScenarioEmailOrderShipped
  alias MyApp.TestingReactorScenarioRecordingEmailService, as: EmailService

  setup do
    {:ok, _email_service} = EmailService.start_link()
    Application.put_env(:my_app, :testing_reactor_scenario_email_service, EmailService)
    on_exit(fn -> Application.delete_env(:my_app, :testing_reactor_scenario_email_service) end)
  end

  test "when an order is shipped a shipping confirmation is sent", %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "order-123",
        %TestingReactorScenarioEmailOrderShipped{order_id: "order-123", carrier: "DHL"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    assert EmailService.sent() == [{"order-123", "DHL"}]
  end
end
```
