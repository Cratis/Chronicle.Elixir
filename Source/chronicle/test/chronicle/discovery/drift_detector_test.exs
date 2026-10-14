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

  defmodule BasketCreated do
    use Chronicle.Events.EventType, id: "drift-basket-created"
    defstruct []
  end

  defmodule ItemAdded do
    use Chronicle.Events.EventType, id: "drift-item-added"
    defstruct item_id: ""
  end

  defmodule NoteAdded do
    use Chronicle.Events.EventType, id: "drift-note-added"
    defstruct item_id: "", text: ""
  end

  defmodule Basket do
    use Chronicle.Projections.Projection, id: "drift-basket", model: __MODULE__
    defstruct basket_id: "", items: []

    from(BasketCreated, set: [basket_id: :event_source_id])

    children :items, identified_by: :item_id do
      from(ItemAdded, key: :item_id, parent_key: :event_source_id, set: [item_id: :item_id])

      children :notes, identified_by: :note_id do
        from(NoteAdded, key: :item_id, set: [text: :text])
      end
    end
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

  # `AllEventTypes` returns the latest generation of each type; derive it from the same
  # fixtures the per-type generations seam serves.
  defp all_fun(responses) do
    fn _channel, _event_store ->
      latest =
        Enum.flat_map(responses, fn {_id, {:ok, generations}} ->
          [Enum.max_by(generations, & &1[:Type][:Generation])]
        end)

      {:ok, latest}
    end
  end

  defp observers_fun(observers) do
    fn _channel, _event_store, _namespace -> {:ok, observers} end
  end

  describe "detect/3" do
    test "finds no drift when the stored schema has the same shape" do
      report = Report.build(%{event_types: [TrackedEvent]})
      schema = Chronicle.Schemas.JsonSchemaGenerator.generate(TrackedEvent, key_transform: :camel)

      stored = %{"tracked-event" => {:ok, [schema_for("tracked-event", 1, schema)]}}

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(stored),
        fetch_event_type_generations_fun: generations_fun(stored),
        fetch_observers_fun: observers_fun([])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "finds schema_changed_without_generation when the stored shape differs" do
      report = Report.build(%{event_types: [TrackedEvent]})

      stored_schema =
        ~s({"type":"object","properties":{"name":{"type":"string"},"extra":{"type":"string"}}})

      stored = %{"tracked-event" => {:ok, [schema_for("tracked-event", 1, stored_schema)]}}

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(stored),
        fetch_event_type_generations_fun: generations_fun(stored),
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
        fetch_all_event_types_fun: all_fun(%{}),
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun:
          observers_fun([observer("orphaned-reactor", :reactor, :client, ["tracked-event"])])
      ]

      assert {:ok, [drift]} = DriftDetector.detect(:fake_channel, report, opts)
      assert drift.kind == :reactor
      assert drift.id == "orphaned-reactor"
      assert drift.reason == :observer_missing_from_code
      assert drift.severity == :info
    end

    test "ignores a kernel-owned observer" do
      report = Report.build(%{})

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(%{}),
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun: observers_fun([observer("kernel-owned", :projection, :kernel, [])])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "finds observer_event_types_changed when handled event types no longer match" do
      report = Report.build(%{reactors: [TrackedReactor]})

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(%{}),
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
        fetch_all_event_types_fun: all_fun(%{}),
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
        fetch_all_event_types_fun: all_fun(%{}),
        fetch_event_type_generations_fun: generations_fun(%{}),
        fetch_observers_fun: fn _channel, _event_store, _namespace -> {:error, :unavailable} end
      ]

      assert {:error, :unavailable} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "a projection's child event types count as handled" do
      report = Report.build(%{projections: [Basket]})

      handled = ["drift-basket-created", "drift-item-added", "drift-note-added"]

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(%{}),
        fetch_observers_fun:
          observers_fun([observer("drift-basket", :projection, :client, handled)])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "observer_missing_from_code is :info for every observer type" do
      report = Report.build(%{})

      for type <- [:reactor, :reducer, :projection] do
        opts = [
          event_store: "store",
          fetch_all_event_types_fun: all_fun(%{}),
          fetch_observers_fun: observers_fun([observer("other-#{type}", type, :client, [])])
        ]

        assert {:ok, [%{severity: :info, reason: :observer_missing_from_code}]} =
                 DriftDetector.detect(:fake_channel, report, opts)
      end
    end

    test "ignores observers on another event sequence" do
      report = Report.build(%{})

      other = %{observer("elsewhere", :reactor, :client, []) | event_sequence_id: "outbox"}

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: all_fun(%{}),
        fetch_observers_fun: observers_fun([other])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "an older local generation fetches that type's generations; a current one does not" do
      report = Report.build(%{event_types: [TrackedEvent]})
      schema = Chronicle.Schemas.JsonSchemaGenerator.generate(TrackedEvent, key_transform: :camel)
      test = self()

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: fn _channel, _store ->
          {:ok, [schema_for("tracked-event", 1, schema)]}
        end,
        fetch_event_type_generations_fun: fn _channel, _store, id ->
          send(test, {:generations_fetched, id})
          {:ok, [schema_for(id, 1, schema)]}
        end,
        fetch_observers_fun: observers_fun([])
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, opts)
      refute_received {:generations_fetched, _}

      newer = [
        fetch_all_event_types_fun: fn _channel, _store ->
          {:ok, [schema_for("tracked-event", 2, schema)]}
        end
      ]

      assert {:ok, []} = DriftDetector.detect(:fake_channel, report, newer ++ opts)
      assert_received {:generations_fetched, "tracked-event"}
    end

    test "returns an error when fetching an event type's generations fails" do
      report = Report.build(%{event_types: [TrackedEvent]})
      schema = Chronicle.Schemas.JsonSchemaGenerator.generate(TrackedEvent, key_transform: :camel)

      opts = [
        event_store: "store",
        fetch_all_event_types_fun: fn _channel, _store ->
          {:ok, [schema_for("tracked-event", 2, schema)]}
        end,
        fetch_event_type_generations_fun: fn _channel, _event_store, _id ->
          {:error, :unavailable}
        end,
        fetch_observers_fun: observers_fun([])
      ]

      assert {:error, :unavailable} = DriftDetector.detect(:fake_channel, report, opts)
    end

    test "returns {:error, :timeout} when the check exceeds its deadline" do
      opts = [
        event_store: "store",
        deadline: 50,
        fetch_all_event_types_fun: fn _channel, _store ->
          Process.sleep(:infinity)
        end,
        fetch_observers_fun: observers_fun([])
      ]

      assert {:error, :timeout} = DriftDetector.detect(:fake_channel, Report.build(%{}), opts)
    end

    test "returns {:error, {:exception, _}} instead of raising" do
      opts = [
        event_store: "store",
        fetch_all_event_types_fun: fn _channel, _store -> raise "boom" end,
        fetch_observers_fun: observers_fun([])
      ]

      assert {:error, {:exception, %RuntimeError{message: "boom"}}} =
               DriftDetector.detect(:fake_channel, Report.build(%{}), opts)
    end
  end
end
