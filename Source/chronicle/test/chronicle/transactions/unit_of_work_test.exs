# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.UnitOfWorkTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventLog

  alias Chronicle.EventSequences.{
    EventForEventSourceId,
    EventSequence,
    TransactionalEventSequence
  }

  alias Chronicle.Transactions.{NoUnitOfWorkStarted, UnitOfWork}

  defmodule TestEvent do
    use Chronicle.EventType, id: "transactions-test-event"

    defstruct [:value]
  end

  setup do
    on_exit(fn ->
      if UnitOfWork.has_current?() do
        UnitOfWork.rollback(UnitOfWork.current())
      end
    end)

    :ok
  end

  test "begin/1 makes the unit of work current and discoverable by correlation id" do
    unit_of_work = UnitOfWork.begin()
    correlation_id = UnitOfWork.correlation_id(unit_of_work)

    assert UnitOfWork.current() == unit_of_work
    assert {:ok, ^unit_of_work} = UnitOfWork.try_get_for(correlation_id)
  end

  test "current/0 raises when no unit of work has been started" do
    assert_raise NoUnitOfWorkStarted, fn ->
      UnitOfWork.current()
    end
  end

  test "append/3 buffers events until the unit of work is committed" do
    parent = self()

    unit_of_work =
      UnitOfWork.begin(
        commit_fun: fn state ->
          send(parent, {:committed, state})
          {:ok, UnitOfWork.default_commit_result([7], [], [])}
        end
      )

    assert :ok = EventLog.append("account-1", %TestEvent{value: 42})

    assert [
             %EventForEventSourceId{
               event_source_id: "account-1",
               event: %TestEvent{value: 42}
             }
           ] = UnitOfWork.get_events(unit_of_work)

    assert :ok = UnitOfWork.commit(unit_of_work)

    assert_received {:committed, %{event_sequence_id: "event-log", events: [_event]}}
    assert UnitOfWork.is_completed?(unit_of_work)
    assert UnitOfWork.is_success?(unit_of_work)
    assert UnitOfWork.last_committed_sequence_number(unit_of_work) == 7
    refute UnitOfWork.has_current?()
  end

  test "append_many/3 buffers each event in insertion order" do
    unit_of_work =
      UnitOfWork.begin(
        commit_fun: fn _state ->
          {:ok, UnitOfWork.default_commit_result([1, 2], [], [])}
        end
      )

    assert :ok =
             EventLog.append_many("account-1", [
               %TestEvent{value: 1},
               %TestEvent{value: 2}
             ])

    assert [
             %EventForEventSourceId{event: %TestEvent{value: 1}},
             %EventForEventSourceId{event: %TestEvent{value: 2}}
           ] = UnitOfWork.get_events(unit_of_work)
  end

  test "transactional event sequences buffer custom event sequence appends" do
    parent = self()

    unit_of_work =
      UnitOfWork.begin(
        commit_fun: fn state ->
          send(parent, {:committed, state})
          {:ok, UnitOfWork.default_commit_result([3], [], [])}
        end
      )

    sequence = EventSequence.new("audit-sequence") |> EventSequence.transactional()

    assert :ok = TransactionalEventSequence.append(sequence, "account-1", %TestEvent{value: 99})

    assert :ok = UnitOfWork.commit(unit_of_work)

    assert_received {:committed,
                     %{event_sequence_id: "audit-sequence", events: [%EventForEventSourceId{}]}}
  end

  test "unit of work rejects buffering events for multiple event sequences" do
    unit_of_work =
      UnitOfWork.begin(
        commit_fun: fn _state ->
          {:ok, UnitOfWork.default_commit_result([], [], [])}
        end
      )

    assert :ok = EventLog.append("account-1", %TestEvent{value: 1})

    sequence = EventSequence.new("audit-sequence") |> EventSequence.transactional()

    assert_raise ArgumentError, ~r/event sequence/, fn ->
      TransactionalEventSequence.append(sequence, "account-1", %TestEvent{value: 2})
    end

    assert [%EventForEventSourceId{event: %TestEvent{value: 1}}] =
             UnitOfWork.get_events(unit_of_work)
  end
end
