# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ObserversTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers
  alias Chronicle.Observers.{ObserverInformation, RemovalResult}

  describe "decode_observer_information/1" do
    test "decodes every field on a wire observer" do
      wire = %{
        Id: "employee-alerts",
        EventSequenceId: "event-log",
        Type: :Reactor,
        RunningState: :Active,
        LastHandledEventSequenceNumber: 6,
        NextEventSequenceNumber: 7,
        HandledEventCount: 6
      }

      assert %ObserverInformation{
               id: "employee-alerts",
               event_sequence_id: "event-log",
               type: :reactor,
               running_state: :active,
               last_handled_event_sequence_number: 6,
               next_event_sequence_number: 7,
               handled_event_count: 6
             } = Observers.decode_observer_information(wire)
    end

    # OBSERVER_RUNNING_STATE_Disconnected is how the wire enum actually names it - protoc
    # prefixes the literal to dodge a collision elsewhere in the file - so a clause matching
    # the plain atom would never fire and every disconnected observer would silently decode
    # as :unknown instead.
    test "decodes a disconnected observer as disconnected, not unknown" do
      wire = %{
        Id: "employee-alerts",
        EventSequenceId: "event-log",
        Type: :Reactor,
        RunningState: :OBSERVER_RUNNING_STATE_Disconnected
      }

      assert %ObserverInformation{running_state: :disconnected} =
               Observers.decode_observer_information(wire)
    end

    test "decodes an unrecognized running state as unknown" do
      wire = %{
        Id: "employee-alerts",
        EventSequenceId: "event-log",
        Type: :Reactor,
        RunningState: :bogus
      }

      assert %ObserverInformation{running_state: :unknown} =
               Observers.decode_observer_information(wire)
    end

    for {wire_type, client_type} <- [
          {:Reactor, :reactor},
          {:Projection, :projection},
          {:Reducer, :reducer},
          {:External, :external}
        ] do
      test "decodes observer type #{wire_type} as #{client_type}" do
        wire = %{
          Id: "an-observer",
          EventSequenceId: "event-log",
          Type: unquote(wire_type),
          RunningState: :Active
        }

        assert %ObserverInformation{type: unquote(client_type)} =
                 Observers.decode_observer_information(wire)
      end
    end
  end

  describe "decode_removal_result/1" do
    test "decodes a removed observer as removed" do
      wire = %{Outcome: :Removed, BlockingNamespace: ""}

      assert %RemovalResult{outcome: :removed, blocking_namespace: ""} =
               Observers.decode_removal_result(wire)

      assert RemovalResult.removed?(Observers.decode_removal_result(wire))
    end

    test "decodes a refusal and the namespace that blocked it" do
      wire = %{Outcome: :ObserverActive, BlockingNamespace: "production"}
      result = Observers.decode_removal_result(wire)

      assert %RemovalResult{outcome: :observer_active, blocking_namespace: "production"} = result
      refute RemovalResult.removed?(result)
    end

    for {wire_outcome, client_outcome} <- [
          {:Removed, :removed},
          {:ObserverNotFound, :observer_not_found},
          {:ObserverActive, :observer_active},
          {:ObserverSubscribed, :observer_subscribed}
        ] do
      test "decodes outcome #{wire_outcome} as #{client_outcome}" do
        wire = %{Outcome: unquote(wire_outcome), BlockingNamespace: ""}

        assert %RemovalResult{outcome: unquote(client_outcome)} =
                 Observers.decode_removal_result(wire)
      end
    end
  end
end
