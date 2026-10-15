```elixir
defmodule MyApp.Events.TestingReactorScenarioRoutedPaymentReceived do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-routed-payment-received"

  defstruct [:amount]
end

defmodule MyApp.Events.TestingReactorScenarioPaymentRouteObserved do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-payment-route-observed"

  defstruct [:amount, :source_type, :stream_type, :stream_id]
end

defmodule MyApp.Reactors.TestingReactorScenarioRouteReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{
    TestingReactorScenarioPaymentRouteObserved,
    TestingReactorScenarioRoutedPaymentReceived
  }

  @handles TestingReactorScenarioRoutedPaymentReceived

  @impl true
  def handle(%TestingReactorScenarioRoutedPaymentReceived{amount: amount}, context) do
    {:ok,
     %TestingReactorScenarioPaymentRouteObserved{
       amount: amount,
       source_type: context.event_source_type,
       stream_type: context.event_stream_type,
       stream_id: context.event_stream_id
     }}
  end
end

defmodule MyApp.TestingReactorScenarioRoutedEventsTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingReactorScenarioRoutedPaymentReceived,
      MyApp.Events.TestingReactorScenarioPaymentRouteObserved
    ],
    reactors: [MyApp.Reactors.TestingReactorScenarioRouteReactor]

  import Chronicle.Testing.Assertions

  alias MyApp.Events.{
    TestingReactorScenarioPaymentRouteObserved,
    TestingReactorScenarioRoutedPaymentReceived
  }

  test "the reactor sees where the event was routed", %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "order-1",
        %TestingReactorScenarioRoutedPaymentReceived{amount: 100},
        client: client,
        event_source_type: "Order",
        event_stream_type: "Payments",
        event_stream_id: "monthly"
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    assert_appended(client, %TestingReactorScenarioPaymentRouteObserved{
      amount: 100,
      source_type: "Order",
      stream_type: "Payments",
      stream_id: "monthly"
    })
  end
end
```
