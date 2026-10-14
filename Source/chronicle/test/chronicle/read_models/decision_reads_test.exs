# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.DecisionReadsTest do
  use ExUnit.Case, async: false

  alias Chronicle.ReadModels.DecisionReads

  defmodule Booked do
    use Chronicle.Events.EventType, id: "drt-booked"
    defstruct []
  end

  defmodule Joiner do
    use Chronicle.Events.EventType, id: "drt-joiner"
    defstruct matching_id: ""
  end

  defmodule PlainSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtPlainSeat"
    defstruct id: "", booked: false
    from(Booked, set: [id: :event_source_id, booked: true])
  end

  defmodule JoinedSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtJoinedSeat"
    defstruct id: "", joined: false
    from(Booked, set: [id: :event_source_id])
    join(Joiner, on: "matchingId", set: [joined: true])
  end

  defmodule RemovedWithJoinSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtRemovedWithJoinSeat"
    defstruct id: ""
    from(Booked, set: [id: :event_source_id])
    removed_with_join(Joiner, key: :matching_id)
  end

  defmodule ChildSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtChildSeat"
    defstruct id: "", items: []

    from(Booked, set: [id: :event_source_id])

    children(:items, from: Joiner, identified_by: :matching_id)
  end

  defmodule OpenEndedSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtOpenEndedSeat"
    defstruct id: "", last_activity: nil
    from(Booked, set: [id: :event_source_id])
    from_every(set: [last_activity: :occurred])
  end

  defmodule CompositeKeySeat do
    use Chronicle.ReadModels.ReadModel, id: "drtCompositeKeySeat"
    defstruct id: "", booked: false

    from(Booked,
      key: {:composite, [{"Id", :event_source_id}]},
      set: [booked: true]
    )
  end

  defmodule ActiveReducerSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtActiveReducerSeat"
    defstruct id: "", booked: false
  end

  defmodule ActiveReducer do
    use Chronicle.Reducers.Reducer, model: ActiveReducerSeat

    @handles Booked

    @impl true
    def reduce(%Booked{}, model, _context), do: model
  end

  defmodule PassiveReducerSeat do
    use Chronicle.ReadModels.ReadModel, id: "drtPassiveReducerSeat"
    defstruct id: "", booked: false
  end

  defmodule PassiveReducer do
    use Chronicle.Reducers.Reducer, model: PassiveReducerSeat, active: false

    @handles Booked

    @impl true
    def reduce(%Booked{}, model, _context), do: model
  end

  # A client that never reaches a kernel - admission is pure, no-I/O logic, so it never needs one.
  setup do
    name = :"decision_reads_admission_#{System.unique_integer([:positive])}"

    {:ok, _} =
      Chronicle.Client.start_link(
        name: name,
        connection_string: "chronicle://localhost:1?disableTls=true",
        event_store: "decision-reads-admission",
        discover: false,
        event_types: [Booked, Joiner],
        reducers: [ActiveReducer, PassiveReducer]
      )

    [opts: [client: name]]
  end

  describe "admit/2" do
    test "admits a plain event-source-keyed projection", %{opts: opts} do
      assert {:ok, [Booked]} = DecisionReads.admit(PlainSeat, opts)
    end

    test "refuses a projection with a join", %{opts: opts} do
      assert {:error, :join} = DecisionReads.admit(JoinedSeat, opts)
    end

    test "refuses a projection with a removed_with_join", %{opts: opts} do
      assert {:error, :join} = DecisionReads.admit(RemovedWithJoinSeat, opts)
    end

    test "refuses a projection with children", %{opts: opts} do
      assert {:error, :hierarchy} = DecisionReads.admit(ChildSeat, opts)
    end

    test "refuses a projection with from_every", %{opts: opts} do
      assert {:error, :open_ended_event_types} = DecisionReads.admit(OpenEndedSeat, opts)
    end

    test "refuses a projection with a non-default key", %{opts: opts} do
      assert {:error, :not_event_source_keyed} = DecisionReads.admit(CompositeKeySeat, opts)
    end

    test "refuses an actively-observed reducer", %{opts: opts} do
      assert {:error, :reducer} = DecisionReads.admit(ActiveReducerSeat, opts)
    end

    test "admits a passive reducer", %{opts: opts} do
      assert {:ok, [Booked]} = DecisionReads.admit(PassiveReducerSeat, opts)
    end

    test "refuses a module that is not a read model at all", %{opts: opts} do
      assert {:error, :not_event_log} = DecisionReads.admit(__MODULE__, opts)
    end
  end

  describe "admit_for_stream/2" do
    test "admits the same shapes as admit/2", %{opts: opts} do
      assert {:ok, [Booked]} = DecisionReads.admit_for_stream(PlainSeat, opts)
      assert {:error, :join} = DecisionReads.admit_for_stream(JoinedSeat, opts)
    end
  end

  describe "get/2" do
    test "returns {:error, :requires_unit_of_work} without an active unit of work", %{
      opts: opts
    } do
      assert {:error, :requires_unit_of_work} = DecisionReads.get(PlainSeat, "seat-1", opts)
    end
  end

  describe "get_detached/3 and get_detached/5 raise DecisionReadRefused for a refused shape" do
    test "model-keyed", %{opts: opts} do
      assert_raise Chronicle.ReadModels.DecisionReadRefused, fn ->
        DecisionReads.get_detached(JoinedSeat, "seat-1", opts)
      end
    end

    test "stream-scoped refuses the default stream before any admission check runs", %{
      opts: opts
    } do
      assert_raise Chronicle.ReadModels.DecisionReadRefused, fn ->
        DecisionReads.get_detached(PlainSeat, "seat-1", "All", "", opts)
      end

      assert_raise Chronicle.ReadModels.DecisionReadRefused, fn ->
        DecisionReads.get_detached(PlainSeat, "seat-1", "", "", opts)
      end
    end
  end
end
