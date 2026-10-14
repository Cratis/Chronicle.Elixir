# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.DriftDetectorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Discovery.{DriftDetector, Report}
  alias Chronicle.Observers.ObserverInformation

  defmodule TrackedEvent do
    use Chronicle.Events.EventType, id: "tracked-event"
    defstruct [:name]
  end

  defmodule TrackedReactor do
    use Chronicle.Reactors.Reactor, id: "tracked-reactor"

    @handles TrackedEvent

    @impl true
    def handle(%TrackedEvent{}, _context), do: :ok
  end

  defp schema_for(event_type_id, generation, schema) do
    %{Type: %{Id: event_type_id, Generation: generation}, Schema: schema}
  end

  defp observer(id, type, owner, event_type_ids) do
    %ObserverInformation{
      id: id,
      event_sequence_id: "event-log",
      type: type,
      owner: owner,
      running_state: :active,
      event_types: Enum.map(event_type_ids, &%{Id: &1, Generation: 1, Tombstone: false})
    }
  end

  defp generations_fun(responses) do
    fn _channel, _event_store, event_type_id ->
      case Map.fetch(responses, event_type_id) do
        {:ok, response} -> response
        :error -> {:ok, []}
      end
    end
  end

  defp observers_fun(observers) do
    fn _channel, _event_store, _namespace -> {:ok, observers} end
  end

  describe "detect/3" do
    test "finds no drift when the stored schema has the same shape" do
      report = Report.build(%{event_types: [TrackedEvent]})
      schema = Chronicle.Schemas.JsonSchemaGenerator.generate(TrackedEvent, key_transform: :camel)

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun:
          generations_fun(%{"tracked-event" => {:ok, [schema_for("tracked-event", 1, schema)]}}),
        fetch_observers_fun: observers_fun([])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "finds schema_changed_without_generation when the stored shape differs" do
      report = Report.build(%{event_types: [TrackedEvent]})

      stored_schema =
        ~s({"type":"object","properties":{"name":{"type":"string"},"extra":{"type":"string"}}})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun:
          generations_fun(%{
            "tracked-event" => {:ok, [schema_for("tracked-event", 1, stored_schema)]}
          }),
        fetch_observers_fun: observers_fun([])
      ]

      assert {:ok, [drift]} = DriftDetector.detect(:fake_channel, report, opts)
      assert drift.kind == :event_type
      assert drift.reason == :schema_changed_without_generation
      assert drift.severity == :warning
    end

    test "finds observer_missing_from_code for a client-owned reactor absent from the report" do
      report = Report.build(%{})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun:
          observers_fun([observer("orphaned-reactor", :reactor, :client, ["tracked-event"])])
      ]

      assert {:ok, [drift]} = DriftDetector.detect(:fake_channel, report, opts)
      assert drift.kind == :reactor
      assert drift.id == "orphaned-reactor"
      assert drift.reason == :observer_missing_from_code
      assert drift.severity == :warning
    end

    test "ignores a kernel-owned observer" do
      report = Report.build(%{})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun: observers_fun([observer("kernel-owned", :projection, :kernel, [])])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "finds observer_event_types_changed when handled event types no longer match" do
      report = Report.build(%{reactors: [TrackedReactor]})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun:
          observers_fun([observer("tracked-reactor", :reactor, :client, ["some-other-event"])])
      ]

      assert {:ok, [drift]} = DriftDetector.detect(:fake_channel, report, opts)
      assert drift.kind == :reactor
      assert drift.id == "tracked-reactor"
      assert drift.reason == :observer_event_types_changed
    end

    test "finds no drift when a reactor's handled event types still match the kernel" do
      report = Report.build(%{reactors: [TrackedReactor]})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun:
          observers_fun([observer("tracked-reactor", :reactor, :client, ["tracked-event"])])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "returns an error when fetching observers fails" do
      report = Report.build(%{})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun: fn _channel, _event_store, _namespace -> {:error, :unavailable} end
      ]

      assert {:error, :unavailable} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "returns an error when fetching an event type's generations fails" do
      report = Report.build(%{event_types: [TrackedEvent]})

      opts = [
        event_store: "store",
        fetch_event_type_generations_fun: fn _channel, _event_store, _id ->
          {:error, :unavailable}
        end,
        fetch_observers_fun: observers_fun([])
      ]

      assert {:error, :unavailable} = DriftDetector.detect(:fake_channel, report, opts)
    end
  end
end
