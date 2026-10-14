```elixir
defmodule MyApp.Events.TestingReadModelScenarioModelBoundShipmentDispatched do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-model-bound-shipment-dispatched"

  defstruct [:carrier]
end

defmodule MyApp.Events.TestingReadModelScenarioModelBoundShipmentDelivered do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-model-bound-shipment-delivered"

  defstruct [:delivered_at]
end

defmodule MyApp.ReadModels.TestingReadModelScenarioModelBoundDeliveryStatus do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    TestingReadModelScenarioModelBoundShipmentDelivered,
    TestingReadModelScenarioModelBoundShipmentDispatched
  }

  defstruct shipment_id: nil, carrier: nil, delivered_at: nil

  from TestingReadModelScenarioModelBoundShipmentDispatched,
    set: [shipment_id: :event_source_id, carrier: :carrier]

  from TestingReadModelScenarioModelBoundShipmentDelivered, set: [delivered_at: :delivered_at]
end

defmodule MyApp.TestingReadModelScenarioModelBoundExampleTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.{
    TestingReadModelScenarioModelBoundShipmentDelivered,
    TestingReadModelScenarioModelBoundShipmentDispatched
  }

  alias MyApp.ReadModels.TestingReadModelScenarioModelBoundDeliveryStatus

  test "a delivered shipment keeps its carrier and gets a delivery time" do
    shipment_id = "shipment-1"

    {:ok, status} =
      Chronicle.Testing.Projections.apply_event(
        TestingReadModelScenarioModelBoundDeliveryStatus,
        nil,
        %TestingReadModelScenarioModelBoundShipmentDispatched{carrier: "FedEx"},
        shipment_id
      )

    {:ok, status} =
      Chronicle.Testing.Projections.apply_event(
        TestingReadModelScenarioModelBoundDeliveryStatus,
        status,
        %TestingReadModelScenarioModelBoundShipmentDelivered{delivered_at: DateTime.utc_now()},
        shipment_id
      )

    assert status.carrier == "FedEx"
    assert %DateTime{} = status.delivered_at
  end
end
```
