```elixir
defmodule MyApp.Events.TestingReactorScenarioDestinationPaymentReceived do
  use Cratis.Chronicle.Events.EventType, id: "testing-reactor-scenario-destination-payment-received"

  defstruct [:amount]
end

defmodule MyApp.Events.TestingReactorScenarioDestinationPaymentRecorded do
  use Cratis.Chronicle.Events.EventType, id: "testing-reactor-scenario-destination-payment-recorded"

  defstruct [:amount]
end

defmodule MyApp.Reactors.TestingReactorScenarioDestinationReactor do
  use Cratis.Chronicle.Reactors.Reactor

  alias Cratis.Chronicle.EventSequences.EventForEventSourceId

  alias MyApp.Events.{
    TestingReactorScenarioDestinationPaymentReceived,
    TestingReactorScenarioDestinationPaymentRecorded
  }

  @handles TestingReactorScenarioDestinationPaymentReceived

  @impl true
  def handle(%TestingReactorScenarioDestinationPaymentReceived{amount: amount}, _context) do
    {:ok,
     %EventForEventSourceId{
       event_source_id: "ledger",
       event: %TestingReactorScenarioDestinationPaymentRecorded{amount: amount},
       event_source_type: "Ledger",
       event_stream_type: "Payments",
       event_stream_id: "monthly"
     }}
  end
end

defmodule MyApp.TestingReactorScenarioProducedDestinationsTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingReactorScenarioDestinationPaymentReceived,
      MyApp.Events.TestingReactorScenarioDestinationPaymentRecorded
    ],
    reactors: [MyApp.Reactors.TestingReactorScenarioDestinationReactor]

  import Cratis.Chronicle.Testing.Assertions

  alias MyApp.Events.{
    TestingReactorScenarioDestinationPaymentReceived,
    TestingReactorScenarioDestinationPaymentRecorded
  }

  test "the reactor records the payment on the ledger", %{chronicle: client} do
    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        "order-1",
        %TestingReactorScenarioDestinationPaymentReceived{amount: 100},
        client: client
      )

    :ok = Cratis.Chronicle.Testing.wait_for_observers(client)

    assert_appended(client, %TestingReactorScenarioDestinationPaymentRecorded{amount: 100},
      event_source_id: "ledger"
    )

    for produced <- Cratis.Chronicle.Testing.appended_events(client, "ledger") do
      context = produced.context
      IO.puts("#{inspect(produced.event.__struct__)}: #{context.event_source_type}/#{context.event_stream_type}/#{context.event_stream_id}")
    end

    [recorded] = Cratis.Chronicle.Testing.appended_events(client, "ledger")
    assert recorded.context.event_source_type == "Ledger"
    assert recorded.context.event_stream_type == "Payments"
    assert recorded.context.event_stream_id == "monthly"
  end
end
```
