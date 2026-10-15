# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.DecideTest do
  use ExUnit.Case, async: true

  alias Chronicle.Transactions.UnitOfWork

  defmodule SeatBooked do
    use Chronicle.Events.EventType, id: "decide-test-seat-booked"
    defstruct by: ""
  end

  defp recording_commit do
    test = self()

    fn state ->
      send(test, {:committed, state.events})
      {:ok, UnitOfWork.default_commit_result([1], [], [])}
    end
  end

  defp failing_commit, do: fn _state -> {:error, :unavailable} end

  defp links, do: Process.info(self(), :links) |> elem(1) |> MapSet.new()

  defp append(id), do: Chronicle.append(id, %SeatBooked{by: "x"})

  describe "decide/2 when the commit fails" do
    test "returns the error and leaves no current unit of work" do
      assert {:error, :unavailable} =
               UnitOfWork.decide(fn _ -> append("seat-1") end, commit_fun: failing_commit())

      refute UnitOfWork.has_current?()
    end

    test "a later append is not buffered into the failed unit of work" do
      UnitOfWork.decide(fn _ -> append("seat-1") end, commit_fun: failing_commit())

      # With no current unit of work the append goes to the event log, which has no client
      # in this spec, instead of silently returning :ok from a dead buffer.
      refute UnitOfWork.has_current?()
      assert {:error, _} = catch_append("seat-2")
    end
  end

  describe "decide/2 when the decision returns an error" do
    test "writes nothing and returns the error unwrapped" do
      result =
        UnitOfWork.decide(
          fn _ ->
            :ok = append("seat-5")
            {:error, :rejected}
          end,
          commit_fun: recording_commit()
        )

      assert {:error, :rejected} = result
      refute_received {:committed, _}
      refute UnitOfWork.has_current?()
    end

    test "a plain :error is committed like any other value" do
      assert {:ok, :error} =
               UnitOfWork.decide(
                 fn _ ->
                   :ok = append("seat-5")
                   :error
                 end,
                 commit_fun: recording_commit()
               )

      assert_received {:committed, [_]}
    end
  end

  describe "the unit of work process" do
    test "is stopped and unlinked after a successful decide/2" do
      before = links()
      {:ok, unit_of_work} = UnitOfWork.decide(fn uow -> uow end, commit_fun: recording_commit())

      refute Process.alive?(unit_of_work)
      assert links() == before
    end

    test "is stopped after a failed commit, a rejected decision and a raise" do
      before = links()

      UnitOfWork.decide(fn _ -> append("seat-1") end, commit_fun: failing_commit())
      UnitOfWork.decide(fn _ -> {:error, :rejected} end, commit_fun: recording_commit())

      assert_raise RuntimeError, fn ->
        UnitOfWork.decide(fn _ -> raise "boom" end, commit_fun: recording_commit())
      end

      assert links() == before
    end

    test "is stopped after with_unit_of_work/2, on success and on failure" do
      before = links()

      assert :done =
               UnitOfWork.with_unit_of_work(fn _ -> :done end, commit_fun: recording_commit())

      assert_raise RuntimeError, fn ->
        UnitOfWork.with_unit_of_work(fn _ -> append("seat-1") end, commit_fun: failing_commit())
      end

      assert links() == before
      refute UnitOfWork.has_current?()
    end

    test "begin/1 leaves the unit of work to its caller" do
      unit_of_work = UnitOfWork.begin(commit_fun: recording_commit())
      assert :ok = UnitOfWork.commit(unit_of_work)
      assert Process.alive?(unit_of_work)
      Agent.stop(unit_of_work)
    end
  end

  defp catch_append(id) do
    append(id)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
