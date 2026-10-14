# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for decision reads / the Dynamic Consistency Boundary
# (issue #140). Opt in like the other integration tests: point
# CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
defmodule Chronicle.Integration.DecisionReadsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReadRefused, DecisionReads}

  defmodule SeatBooked do
    use Chronicle.Events.EventType, id: "dr-seat-booked"
    defstruct by: ""
  end

  # A unique-seat-booking model: a decision read on it guards "is this seat still free" the way
  # the DCB docs' two-key course-subscription example guards one side of a rule.
  defmodule Seat do
    use Chronicle.ReadModels.ReadModel, id: "drSeat"

    defstruct id: "", booked_by: ""

    from(SeatBooked, set: [id: :event_source_id, booked_by: :by])
  end

  # Refused: `join/2` means a match can come from outside the guarded event source.
  defmodule JoinSource do
    use Chronicle.Events.EventType, id: "dr-join-source"
    defstruct matching_id: ""
  end

  defmodule Joined do
    use Chronicle.ReadModels.ReadModel, id: "drJoined"

    defstruct id: "", matching_id: ""

    from(SeatBooked, set: [id: :event_source_id])
    join(JoinSource, on: "matchingId", set: [matching_id: :matching_id])
  end

  defmodule WithdrawalsSeat do
    use Chronicle.ReadModels.ReadModel, id: "drWithdrawalsSeat"

    defstruct id: "", booked_by: ""
  end

  defmodule PassiveSeatReducer do
    use Chronicle.Reducers.Reducer, model: WithdrawalsSeat, active: false

    @handles SeatBooked

    @impl true
    def reduce(%SeatBooked{by: by}, _model, context) do
      %WithdrawalsSeat{id: context.event_source_id, booked_by: by}
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "decision-reads-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :decision_reads_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [SeatBooked, JoinSource],
        read_models: [Seat, Joined],
        reducers: [PassiveSeatReducer]
      )

    :ok = Chronicle.Client.await_registration(:decision_reads_it_client, 60_000)
    :ok
  end

  @opts [client: :decision_reads_it_client]

  defp unique_seat_id, do: "seat-#{System.unique_integer([:positive])}"

  test "admit/2 admits a plain event-source-keyed projection" do
    assert {:ok, [SeatBooked]} = DecisionReads.admit(Seat, @opts)
  end

  test "admit/2 refuses a projection with a join" do
    assert {:error, :join} = DecisionReads.admit(Joined, @opts)
  end

  test "get_detached/3 raises DecisionReadRefused for a refused shape" do
    assert_raise DecisionReadRefused, fn ->
      DecisionReads.get_detached(Joined, unique_seat_id(), @opts)
    end
  end

  test "get_detached/5 refuses the default stream with :all_streams_not_supported" do
    seat_id = unique_seat_id()

    assert_raise DecisionReadRefused, fn ->
      DecisionReads.get_detached(Seat, seat_id, "All", "", @opts)
    end

    assert_raise DecisionReadRefused, fn ->
      DecisionReads.get_detached(Seat, seat_id, "", "", @opts)
    end
  end

  test "get/3 returns {:error, :requires_unit_of_work} outside a unit of work" do
    assert {:error, :requires_unit_of_work} = DecisionReads.get(Seat, unique_seat_id(), @opts)
  end

  test "get_detached/3 returns the current (absent) instance without a unit of work" do
    assert {:ok, %{instance: nil}} = DecisionReads.get_detached(Seat, unique_seat_id(), @opts)
  end

  test "decide/2 commits normally when nothing conflicts" do
    seat_id = unique_seat_id()

    result =
      Chronicle.decide(
        fn _unit_of_work ->
          {:ok, read} = DecisionReads.get(Seat, seat_id, @opts)
          assert read.instance == nil
          :ok = EventLog.append(seat_id, %SeatBooked{by: "alice"}, @opts)
          :booked
        end,
        @opts
      )

    assert {:ok, :booked} = result
    assert {:ok, %{instance: seat}} = DecisionReads.get_detached(Seat, seat_id, @opts)
    assert seat.booked_by == "alice"
  end

  test "an append to the guarded event source between the read and the commit is rejected" do
    seat_id = unique_seat_id()

    result =
      Chronicle.decide(
        fn _unit_of_work ->
          {:ok, _read} = DecisionReads.get(Seat, seat_id, @opts)

          # A separate process races in and books the seat directly - on its own connection
          # process, so it is not buffered in this unit of work - after the boundary above was
          # captured but before this unit of work commits.
          Task.async(fn ->
            EventLog.append_and_wait_for_completion(seat_id, %SeatBooked{by: "mallory"}, @opts)
          end)
          |> Task.await()

          :ok = EventLog.append(seat_id, %SeatBooked{by: "alice"}, @opts)
          :booked
        end,
        @opts
      )

    assert {:error, %DecisionConflict{}} = result

    # Neither of this attempt's own appends landed; only mallory's direct booking did.
    assert {:ok, %{instance: seat}} = DecisionReads.get_detached(Seat, seat_id, @opts)
    assert seat.booked_by == "mallory"
  end

  test "a passive reducer's read model can back a decision read" do
    seat_id = unique_seat_id()

    assert {:ok, %{instance: nil}} = DecisionReads.get_detached(WithdrawalsSeat, seat_id, @opts)

    assert {:ok, %{success: true}} =
             EventLog.append_and_wait_for_completion(seat_id, %SeatBooked{by: "carol"}, @opts)

    assert {:ok, %{instance: %WithdrawalsSeat{booked_by: "carol"}}} =
             DecisionReads.get_detached(WithdrawalsSeat, seat_id, @opts)
  end
end
