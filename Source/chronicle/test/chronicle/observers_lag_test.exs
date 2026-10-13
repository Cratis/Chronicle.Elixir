# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.LagTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.Lag
  alias Chronicle.Observers.ObserverInformation

  defp observer(handled) do
    %ObserverInformation{
      id: "r",
      event_sequence_id: "event-log",
      type: :reactor,
      running_state: :active,
      last_handled_event_sequence_number: handled
    }
  end

  test "lag is the distance from the tail to the last handled event" do
    assert %{lag: 7, tail: 10, last_handled: 3, observer_id: "r"} = Lag.entry(observer(3), 10)
  end

  test "an observer that has caught up has no lag, and never a negative one" do
    assert Lag.entry(observer(10), 10).lag == 0
    assert Lag.entry(observer(12), 10).lag == 0
  end

  test "the reporter publishes a telemetry event per observer" do
    id = {__MODULE__, make_ref()}
    test = self()

    :telemetry.attach(
      id,
      [:chronicle, :observer, :lag],
      fn _event, measurements, metadata, _ -> send(test, {:lag, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    Lag.Reporter.publish(Lag.entry(observer(3), 10), :my_client)

    assert_receive {:lag, %{lag: 7, tail: 10},
                    %{observer_id: "r", client: :my_client, type: :reactor}}
  end
end
