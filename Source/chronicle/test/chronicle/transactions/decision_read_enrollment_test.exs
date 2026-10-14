# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.DecisionReadEnrollmentTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.ReadModels.{DecisionConflict, DecisionRead}
  alias Chronicle.Transactions.UnitOfWork

  defmodule TestEvent do
    use Chronicle.Events.EventType, id: "decision-read-enrollment-event"
    defstruct [:value]
  end

  defmodule SomeModel, do: defstruct([:id])

  defmodule OtherEvent do
    use Chronicle.Events.EventType, id: "decision-read-enrollment-other-event"
    defstruct []
  end

  setup do
    on_exit(fn ->
      if UnitOfWork.has_current?() do
        UnitOfWork.rollback(UnitOfWork.current())
      end
    end)

    :ok
  end

  defp read(event_source_id, scope_opts) do
    %DecisionRead{
      read_model: SomeModel,
      key: event_source_id,
      instance: nil,
      event_source_id: event_source_id,
      event_store: "store",
      namespace: "namespace",
      event_sequence_id: "event-log",
      scope: ConcurrencyScope.new(Keyword.get(scope_opts, :sequence_number, 0), scope_opts),
      event_types: Keyword.get(scope_opts, :event_types, [TestEvent])
    }
  end

  describe "add_decision_read/2" do
    test "enrolls a read and exposes its scope via get_decision_reads/1" do
      unit_of_work = UnitOfWork.begin()
      :ok = UnitOfWork.add_decision_read(unit_of_work, read("account-1", sequence_number: 5))

      assert %{"account-1" => %ConcurrencyScope{sequence_number: 5}} =
               UnitOfWork.get_decision_reads(unit_of_work)

      assert UnitOfWork.has_decision_reads?(unit_of_work)
    end

    test "merges two reads of the same source at their earliest boundary, union of types" do
      unit_of_work = UnitOfWork.begin()

      :ok =
        UnitOfWork.add_decision_read(
          unit_of_work,
          read("account-1", sequence_number: 9, event_types: [TestEvent])
        )

      :ok =
        UnitOfWork.add_decision_read(
          unit_of_work,
          read("account-1", sequence_number: 3, event_types: [OtherEvent])
        )

      assert %{
               "account-1" => %ConcurrencyScope{
                 sequence_number: 3,
                 event_types: event_types
               }
             } = UnitOfWork.get_decision_reads(unit_of_work)

      assert Enum.sort(event_types) == Enum.sort([TestEvent, OtherEvent])
    end

    test "merging two expecting_no_matching_event reads keeps that expectation" do
      scope = ConcurrencyScope.expecting_no_matching_event(event_source_id: true)

      first = %DecisionRead{
        read_model: SomeModel,
        key: "account-1",
        event_source_id: "account-1",
        event_store: "store",
        namespace: "namespace",
        event_sequence_id: "event-log",
        scope: scope,
        event_types: [TestEvent]
      }

      second = %{first | event_types: [TestEvent]}

      unit_of_work = UnitOfWork.begin()
      :ok = UnitOfWork.add_decision_read(unit_of_work, first)
      :ok = UnitOfWork.add_decision_read(unit_of_work, second)

      assert %{"account-1" => %ConcurrencyScope{expects_no_matching_event: true}} =
               UnitOfWork.get_decision_reads(unit_of_work)
    end

    test "refuses enrollment once the unit of work has committed" do
      unit_of_work = UnitOfWork.begin(commit_fun: fn _ -> {:ok, %{}} end)
      :ok = UnitOfWork.commit(unit_of_work)

      assert_raise Chronicle.Transactions.UnitOfWorkIsAlreadyCommitted, fn ->
        UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))
      end
    end

    test "refuses an explicit concurrency scope on the same source as a buffered event" do
      unit_of_work = UnitOfWork.begin()

      event = %EventForEventSourceId{
        event_source_id: "account-1",
        event: %TestEvent{value: 1},
        concurrency_scope: ConcurrencyScope.for_event_source(7)
      }

      :ok = UnitOfWork.add_event(unit_of_work, "event-log", event)

      assert_raise ArgumentError, ~r/explicit concurrency/, fn ->
        UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))
      end
    end

    test "refuses an event with an explicit concurrency scope on an already-enrolled source" do
      unit_of_work = UnitOfWork.begin()
      :ok = UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))

      event = %EventForEventSourceId{
        event_source_id: "account-1",
        event: %TestEvent{value: 1},
        concurrency_scope: ConcurrencyScope.for_event_source(7)
      }

      assert_raise ArgumentError, ~r/already enrolled as a decision read/, fn ->
        UnitOfWork.add_event(unit_of_work, "event-log", event)
      end
    end

    test "an event with no explicit concurrency scope can share a source with a decision read" do
      unit_of_work = UnitOfWork.begin()
      :ok = UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))

      event = %EventForEventSourceId{event_source_id: "account-1", event: %TestEvent{value: 1}}
      assert :ok = UnitOfWork.add_event(unit_of_work, "event-log", event)
      assert [^event] = UnitOfWork.get_events(unit_of_work)
    end
  end

  describe "with_unit_of_work/2 and decide/2 on a concurrency conflict" do
    defp conflicting_commit_fun(_state) do
      {:ok,
       %{
         append_results: [],
         constraint_violations: [],
         append_errors: [],
         last_sequence_number: nil,
         success?: false,
         error: {:concurrency_violations, [%{EventSourceId: "account-1"}]}
       }}
    end

    test "decide/2 returns {:error, %DecisionConflict{}} when a decision read was enrolled" do
      result =
        UnitOfWork.decide(
          fn unit_of_work ->
            :ok = UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))
            :proceeding
          end,
          commit_fun: &conflicting_commit_fun/1
        )

      assert {:error, %DecisionConflict{violations: [%{EventSourceId: "account-1"}]}} = result
    end

    test "decide/2 returns the raw error when no decision read was enrolled" do
      result =
        UnitOfWork.decide(fn _unit_of_work -> :proceeding end,
          commit_fun: &conflicting_commit_fun/1
        )

      assert {:error, {:concurrency_violations, [%{EventSourceId: "account-1"}]}} = result
    end

    test "with_unit_of_work/2 raises DecisionConflict when a decision read was enrolled" do
      assert_raise DecisionConflict, fn ->
        UnitOfWork.with_unit_of_work(
          fn unit_of_work ->
            :ok = UnitOfWork.add_decision_read(unit_of_work, read("account-1", []))
            :proceeding
          end,
          commit_fun: &conflicting_commit_fun/1
        )
      end
    end

    test "with_unit_of_work/2 raises a plain error when no decision read was enrolled" do
      assert_raise RuntimeError, ~r/concurrency_violations/, fn ->
        UnitOfWork.with_unit_of_work(fn _unit_of_work -> :proceeding end,
          commit_fun: &conflicting_commit_fun/1
        )
      end
    end

    test "decide/2 returns {:ok, result} on a clean commit" do
      assert {:ok, :done} =
               UnitOfWork.decide(fn _unit_of_work -> :done end,
                 commit_fun: fn _ -> {:ok, UnitOfWork.default_commit_result([1], [], [])} end
               )
    end
  end
end
