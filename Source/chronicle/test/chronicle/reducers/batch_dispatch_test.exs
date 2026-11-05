# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.BatchDispatchTest do
  use ExUnit.Case, async: false

  alias Chronicle.Observers.{BatchContext, BatchFunctions}
  alias Chronicle.Reducers.{Dispatch, Handler}

  defmodule Deposited do
    use Chronicle.Events.EventType, id: "reducer-batch-deposited"
    defstruct [:amount]
  end

  defmodule Account do
    use Chronicle.ReadModels.ReadModel
    defstruct [:balance]
  end

  defmodule BatchAccountReducer do
    use Chronicle.Reducers.Reducer, model: Account

    # Defers when a deposit of 0 is seen and fails when a negative deposit is seen.
    @observes Deposited
    def fold(events, current, context) do
      send(
        :persistent_term.get({__MODULE__, :test}),
        {:fold, self(), Enum.map(events, fn {event, _ctx} -> event.amount end), current, context}
      )

      cond do
        Enum.any?(events, fn {event, _ctx} -> event.amount == 0 end) ->
          {:defer, 1_000}

        Enum.any?(events, fn {event, _ctx} -> event.amount < 0 end) ->
          {:error, :negative}

        true ->
          %Account{balance: balance(current) + Enum.sum_by(events, fn {e, _} -> e.amount end)}
      end
    end

    defp balance(nil), do: 0
    defp balance(%Account{balance: balance}), do: balance
  end

  defmodule PerEventAccountReducer do
    use Chronicle.Reducers.Reducer, model: Account

    @handles Deposited

    @impl true
    def reduce(%Deposited{amount: amount}, nil, _context), do: %Account{balance: amount}

    def reduce(%Deposited{amount: amount}, account, _context),
      do: %{account | balance: account.balance + amount}
  end

  setup do
    :persistent_term.put({BatchAccountReducer, :test}, self())
    :ok
  end

  defp state(module, opts \\ []) do
    %{
      module: module,
      event_type_map: %{"reducer-batch-deposited" => Deposited},
      batch_functions: BatchFunctions.validate!(:reducer, module).batch,
      max_concurrency: Keyword.get(opts, :max_concurrency, 4),
      model_module: Account
    }
  end

  defp deposit(partition, sequence_number, amount) do
    %{
      Context: %{
        EventType: %{Id: "reducer-batch-deposited", Generation: 1},
        EventSourceId: partition,
        SequenceNumber: sequence_number
      },
      Content: Jason.encode!(%{amount: amount})
    }
  end

  defp page(partitions) do
    %{
      DeliveryId: 21,
      Origin: :CatchingUp,
      Partitions:
        Enum.map(partitions, fn {partition, initial_state, events} ->
          %{Partition: partition, InitialState: initial_state, Events: events}
        end)
    }
  end

  defp result(message), do: message |> Map.fetch!(:Content) |> Map.fetch!(:Value1)

  defp by_partition(message),
    do:
      message |> result() |> Map.fetch!(:Partitions) |> Map.new(&{Map.fetch!(&1, :Partition), &1})

  defp balance_of(partition_result) do
    partition_result |> Map.fetch!(:ReadModelState) |> Jason.decode!() |> Map.fetch!("balance")
  end

  test "calls the batch function once per event source, with its events and stored state" do
    stored = Chronicle.Serialization.to_json(%Account{balance: 100}, :identity)

    message =
      Dispatch.build_result(
        state(BatchAccountReducer),
        page([
          {"a", stored, [deposit("a", 1, 5), deposit("a", 3, 7)]},
          {"b", "", [deposit("b", 2, 1)]}
        ])
      )

    assert_received {:fold, _, [5, 7], %Account{balance: 100}, %BatchContext{} = context}
    assert_received {:fold, _, [1], nil, _context}
    refute_received {:fold, _, _, _, _}
    assert context.origin == :catch_up
    assert context.partitions == ["a", "b"]

    assert Map.fetch!(result(message), :DeliveryId) == 21
    assert %{State: 1, LastSuccessfulObservation: 3} = by_partition(message)["a"]
    assert balance_of(by_partition(message)["a"]) == 112
    assert balance_of(by_partition(message)["b"]) == 1
  end

  test "reduces the event sources of a page concurrently" do
    Dispatch.build_result(
      state(BatchAccountReducer, max_concurrency: 2),
      page([{"a", "", [deposit("a", 1, 1)]}, {"b", "", [deposit("b", 2, 1)]}])
    )

    assert_received {:fold, first, _, _, _}
    assert_received {:fold, second, _, _, _}
    assert first != second
  end

  test "defers an event source and writes no state for it" do
    message =
      Dispatch.build_result(
        state(BatchAccountReducer),
        page([{"a", "", [deposit("a", 1, 0)]}, {"b", "", [deposit("b", 2, 4)]}])
      )

    assert %{State: 3, RetryAfterMilliseconds: 1_000, ReadModelState: ""} =
             by_partition(message)["a"]

    assert %{State: 1} = by_partition(message)["b"]
  end

  test "fails an event source the batch function failed" do
    message =
      Dispatch.build_result(state(BatchAccountReducer), page([{"a", "", [deposit("a", 1, -1)]}]))

    assert %{State: 2, LastSuccessfulObservation: 0, ExceptionMessages: [":negative"]} =
             by_partition(message)["a"]
  end

  test "folds per-event reducers over each event source of a page" do
    message =
      Dispatch.build_result(
        state(PerEventAccountReducer),
        page([
          {"a", "", [deposit("a", 1, 2), deposit("a", 4, 3)]},
          {"b", "", [deposit("b", 2, 9)]}
        ])
      )

    assert balance_of(by_partition(message)["a"]) == 5
    assert balance_of(by_partition(message)["b"]) == 9
  end

  describe "a single read model from a kernel that predates pages" do
    test "answers in the single-partition shape" do
      message =
        Dispatch.build_result(state(BatchAccountReducer), %{
          Partition: "a",
          InitialState: "",
          DeliveryId: 3,
          Events: [deposit("a", 9, 4)]
        })

      assert_received {:fold, _, [4], nil, %BatchContext{can_defer?: false}}

      assert %{Partition: "a", State: 1, LastSuccessfulObservation: 9, DeliveryId: 3} =
               result(message)

      assert balance_of(result(message)) == 4
    end

    test "fails a deferral, since the kernel cannot defer" do
      message =
        Dispatch.build_result(state(BatchAccountReducer), %{
          Partition: "a",
          InitialState: "",
          Events: [deposit("a", 9, 0)]
        })

      assert %{State: 2, ExceptionStackTrace: reason} = result(message)
      assert reason =~ "cannot be deferred"
    end
  end

  test "opts in to page delivery when it registers" do
    state = %{
      module: BatchAccountReducer,
      model_module: Account,
      event_store: "store",
      namespace: "Default",
      event_type_map: %{"reducer-batch-deposited" => Deposited},
      generation_delivery: :compatibility
    }

    registration =
      state |> Handler.build_registration("conn-1") |> Map.fetch!(:Content) |> Map.fetch!(:Value0)

    assert %{Enabled: true} = Map.fetch!(registration, :PageDelivery)
  end
end
