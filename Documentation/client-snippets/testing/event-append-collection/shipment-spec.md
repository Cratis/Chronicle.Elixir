```elixir
defmodule MyApp.TestingCollectionShipmentSpecTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingCollectionOrderPlaced,
      MyApp.Events.TestingCollectionShipmentScheduled
    ],
    reactors: [MyApp.Reactors.TestingCollectionShipmentReactor]

  alias MyApp.Events.{TestingCollectionOrderPlaced, TestingCollectionShipmentScheduled}

  test "a reactor's follow-up append is captured once observers have settled", %{chronicle: client} do
    order_id = "order-#{System.unique_integer([:positive])}"

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        order_id,
        %TestingCollectionOrderPlaced{order_id: order_id},
        client: client
      )

    # Wait for the reactor's follow-up append to arrive — deterministic, no sleeps.
    :ok = Cratis.Chronicle.Testing.wait_for_observers(client)

    shipment =
      client
      |> Cratis.Chronicle.Testing.appended_events(order_id)
      |> Enum.map(& &1.event)
      |> Enum.find(&match?(%TestingCollectionShipmentScheduled{}, &1))

    assert %TestingCollectionShipmentScheduled{order_id: ^order_id} = shipment
  end
end
```
