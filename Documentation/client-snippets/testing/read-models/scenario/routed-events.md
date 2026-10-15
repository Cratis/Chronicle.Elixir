```elixir
defmodule MyApp.Events.TestingReadModelScenarioPaymentReceived do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-payment-received"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.TestingReadModelScenarioPaymentRoute do
  defstruct amount: 0, source_type: nil, stream_type: nil, stream_id: nil
end

defmodule MyApp.Reducers.TestingReadModelScenarioPaymentRouteReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.TestingReadModelScenarioPaymentRoute

  alias MyApp.Events.TestingReadModelScenarioPaymentReceived
  alias MyApp.ReadModels.TestingReadModelScenarioPaymentRoute

  @handles TestingReadModelScenarioPaymentReceived

  @impl true
  def reduce(%TestingReadModelScenarioPaymentReceived{amount: amount}, _model, context) do
    %TestingReadModelScenarioPaymentRoute{
      amount: amount,
      source_type: context.event_source_type,
      stream_type: context.event_stream_type,
      stream_id: context.event_stream_id
    }
  end
end

defmodule MyApp.TestingReadModelScenarioRoutedEventsTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReadModelScenarioPaymentReceived],
    reducers: [MyApp.Reducers.TestingReadModelScenarioPaymentRouteReducer]

  alias MyApp.Events.TestingReadModelScenarioPaymentReceived
  alias MyApp.Reducers.TestingReadModelScenarioPaymentRouteReducer

  setup %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "order-1",
        %TestingReadModelScenarioPaymentReceived{amount: 42},
        client: client,
        event_source_type: "Order",
        event_stream_type: "Payments",
        event_stream_id: "2026-10"
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    {:ok, route} =
      Chronicle.Testing.read_model(client, TestingReadModelScenarioPaymentRouteReducer, "order-1")

    %{route: route}
  end

  test "sees the source type", %{route: route}, do: assert(route.source_type == "Order")
  test "sees the stream type", %{route: route}, do: assert(route.stream_type == "Payments")
  test "sees the stream id", %{route: route}, do: assert(route.stream_id == "2026-10")
end
```
