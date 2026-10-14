```elixir
defmodule MyApp.Events.TestingReactorScenarioServicesBookingCancelled do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-services-booking-cancelled"

  defstruct [:booking_id]
end

defmodule MyApp.TestingReactorScenarioServicesNotifications do
  @callback notify(String.t()) :: :ok
end

defmodule MyApp.Reactors.TestingReactorScenarioServicesCancellationReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingReactorScenarioServicesBookingCancelled

  @handles TestingReactorScenarioServicesBookingCancelled

  @impl true
  def handle(%TestingReactorScenarioServicesBookingCancelled{booking_id: booking_id}, _context) do
    notifications = Application.fetch_env!(:my_app, :testing_reactor_scenario_notifications)
    notifications.notify("Booking #{booking_id} was cancelled.")
  end
end

defmodule MyApp.TestingReactorScenarioServicesRecordingNotifications do
  @behaviour MyApp.TestingReactorScenarioServicesNotifications

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def messages, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def notify(message), do: Agent.update(__MODULE__, &[message | &1])
end

defmodule MyApp.TestingReactorScenarioServicesTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReactorScenarioServicesBookingCancelled],
    reactors: [MyApp.Reactors.TestingReactorScenarioServicesCancellationReactor]

  alias MyApp.Events.TestingReactorScenarioServicesBookingCancelled
  alias MyApp.TestingReactorScenarioServicesRecordingNotifications, as: Notifications

  setup do
    # Register the stand-in the reactor will resolve
    {:ok, _notifications} = Notifications.start_link()
    Application.put_env(:my_app, :testing_reactor_scenario_notifications, Notifications)
    on_exit(fn -> Application.delete_env(:my_app, :testing_reactor_scenario_notifications) end)
  end

  test "a cancelled booking sends a notification", %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "booking-123",
        %TestingReactorScenarioServicesBookingCancelled{booking_id: "booking-123"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    assert Notifications.messages() == ["Booking booking-123 was cancelled."]
  end
end
```
