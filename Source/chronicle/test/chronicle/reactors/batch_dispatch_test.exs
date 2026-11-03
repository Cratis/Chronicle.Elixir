# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.BatchDispatchTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Observers.{BatchContext, BatchFunctions, EventBatch}
  alias Chronicle.Reactors.{Dispatch, Handler}

  defmodule Registered do
    use Chronicle.Events.EventType, id: "batch-dispatch-registered"
    defstruct [:name]
  end

  defmodule Removed do
    use Chronicle.Events.EventType, id: "batch-dispatch-removed"
    defstruct [:name]
  end

  defmodule EmailChanged do
    use Chronicle.Events.EventType, id: "batch-dispatch-email-changed"
    defstruct [:name]
  end

  defmodule UsersReactor do
    use Chronicle.Reactors.Reactor

    @handles EmailChanged

    # Fails the partition of an event named "fail" from that event, defers the partition of an
    # event named "defer" and raises for an event named "raise".
    @observes Registered
    @observes Removed
    def index(batch, context) do
      notify(
        {:index, Enum.map(batch, fn {event, ctx} -> {event.name, ctx.sequence_number} end),
         context}
      )

      Enum.reduce(batch, batch, fn
        {%{name: "fail"}, ctx}, reported -> EventBatch.fail(reported, ctx, :index_unavailable)
        {%{name: "defer"}, ctx}, reported -> EventBatch.defer(reported, ctx, 250)
        {%{name: "raise"}, _ctx}, _reported -> raise "index exploded"
        {%{name: "events"}, _ctx}, _reported -> throw(:events)
        _, reported -> reported
      end)
    catch
      :events -> {:ok, [%Registered{name: "side effect"}]}
    end

    @impl true
    def handle(%EmailChanged{name: name}, context) do
      notify({:handle, name, context.sequence_number})
      if name == "boom", do: {:error, :email_unavailable}, else: :ok
    end

    defp notify(message), do: send(:persistent_term.get({__MODULE__, :test}), message)
  end

  defmodule PerEventReactor do
    use Chronicle.Reactors.Reactor

    @handles EmailChanged

    @impl true
    def handle(%EmailChanged{name: name}, context) do
      send(:persistent_term.get({UsersReactor, :test}), {:handle, name, context.sequence_number})
      :ok
    end
  end

  defmodule Confused do
    use Chronicle.Reactors.Reactor

    @handles Registered

    @observes Registered
    def index(_batch, _context), do: :ok

    @impl true
    def handle(_event, _context), do: :ok
  end

  setup do
    :persistent_term.put({UsersReactor, :test}, self())
    :ok
  end

  defp state(module) do
    %{
      module: module,
      event_store: "store",
      namespace: "Default",
      event_type_map:
        Map.new(module.__chronicle_reactor__(:handles), &{&1.__chronicle_event_type__(:id), &1}),
      batch_functions: BatchFunctions.validate!(:reactor, module).batch,
      append_fun: fn operation -> send(self(), {:appended, operation}) && :ok end
    }
  end

  defp event(module, partition, sequence_number, name) do
    %{
      Context: %{
        EventType: %{Id: module.__chronicle_event_type__(:id), Generation: 1},
        EventSourceId: partition,
        SequenceNumber: sequence_number
      },
      Content: Jason.encode!(%{name: name})
    }
  end

  defp page(partitions, origin \\ :Live) do
    %{
      DeliveryId: 11,
      Origin: origin,
      Partitions:
        Enum.map(partitions, fn {partition, events} -> %{Partition: partition, Events: events} end)
    }
  end

  defp result(message), do: message |> Map.fetch!(:Content) |> Map.fetch!(:Value1)

  defp by_partition(message),
    do:
      message |> result() |> Map.fetch!(:Partitions) |> Map.new(&{Map.fetch!(&1, :Partition), &1})

  describe "a page" do
    test "calls the batch function once, with every observed event of the page in order" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([
            {"a", [event(Registered, "a", 1, "ann"), event(Removed, "a", 4, "ann")]},
            {"b", [event(Registered, "b", 2, "bob")]}
          ])
        )

      assert_received {:index, [{"ann", 1}, {"bob", 2}, {"ann", 4}], %BatchContext{} = context}
      refute_received {:index, _, _}
      assert context.origin == :live
      assert context.can_defer?
      assert context.partitions == ["a", "b"]
      assert context.event_count == 3

      assert Map.fetch!(result(message), :DeliveryId) == 11
      assert %{State: 1, LastSuccessfulObservation: 4} = by_partition(message)["a"]
      assert %{State: 1, LastSuccessfulObservation: 2} = by_partition(message)["b"]
    end

    test "sends each event type to exactly one function, keeping order per function" do
      Dispatch.build_result(
        state(UsersReactor),
        page([
          {"a",
           [
             event(EmailChanged, "a", 1, "first"),
             event(Registered, "a", 2, "ann"),
             event(EmailChanged, "a", 3, "second")
           ]}
        ])
      )

      assert_received {:index, [{"ann", 2}], _context}
      assert_received {:handle, "first", 1}
      assert_received {:handle, "second", 3}
      refute_received {:handle, "ann", _}
    end

    test "dispatches every partition to per-event handlers in order" do
      message =
        Dispatch.build_result(
          state(PerEventReactor),
          page([
            {"a", [event(EmailChanged, "a", 1, "one"), event(EmailChanged, "a", 3, "three")]},
            {"b", [event(EmailChanged, "b", 2, "two")]}
          ])
        )

      assert_received {:handle, "one", 1}
      assert_received {:handle, "three", 3}
      assert_received {:handle, "two", 2}
      assert map_size(by_partition(message)) == 2
    end

    test "passes where the page came from" do
      Dispatch.build_result(
        state(UsersReactor),
        page([{"a", [event(Registered, "a", 1, "ann")]}], :Replaying)
      )

      assert_received {:index, _, %BatchContext{origin: :replay} = context}
      assert BatchContext.replay?(context)
    end
  end

  describe "settling the partitions of a page" do
    test "fails only the partition a batch function failed, from that event" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([
            {"a",
             [
               event(Registered, "a", 1, "ann"),
               event(Registered, "a", 3, "fail"),
               event(Registered, "a", 5, "later")
             ]},
            {"b", [event(Registered, "b", 2, "bob")]}
          ])
        )

      assert %{State: 2, LastSuccessfulObservation: 1, ExceptionMessages: [":index_unavailable"]} =
               by_partition(message)["a"]

      assert %{State: 1, LastSuccessfulObservation: 2} = by_partition(message)["b"]
    end

    test "defers a partition with its delay" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([{"a", [event(Registered, "a", 1, "ann"), event(Registered, "a", 2, "defer")]}])
        )

      assert %{State: 3, LastSuccessfulObservation: 1, RetryAfterMilliseconds: 250} =
               by_partition(message)["a"]
    end

    test "settles a partition at the earliest problem any function reported" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([
            {"a",
             [
               event(EmailChanged, "a", 1, "ok"),
               event(EmailChanged, "a", 2, "boom"),
               event(Registered, "a", 3, "fail")
             ]}
          ])
        )

      assert %{State: 2, LastSuccessfulObservation: 1, ExceptionMessages: [":email_unavailable"]} =
               by_partition(message)["a"]
    end

    test "fails every partition of the batch at its first event when the function raises" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([
            {"a", [event(EmailChanged, "a", 1, "ok"), event(Registered, "a", 2, "raise")]},
            {"b", [event(Registered, "b", 3, "bob")]}
          ])
        )

      assert %{State: 2, LastSuccessfulObservation: 1} = by_partition(message)["a"]
      assert %{State: 2, LastSuccessfulObservation: 0} = by_partition(message)["b"]
    end

    test "refuses events returned from a batch function" do
      message =
        Dispatch.build_result(
          state(UsersReactor),
          page([{"a", [event(Registered, "a", 1, "events")]}])
        )

      assert %{State: 2, ExceptionMessages: [reason]} = by_partition(message)["a"]
      assert reason =~ "returning events is not supported"
      refute_received {:appended, _}
    end
  end

  describe "a single partition from a kernel that predates pages" do
    test "answers in the single-partition shape" do
      message =
        Dispatch.build_result(state(UsersReactor), %{
          Partition: "a",
          DeliveryId: 5,
          Events: [event(Registered, "a", 7, "ann")]
        })

      assert_received {:index, [{"ann", 7}], %BatchContext{can_defer?: false}}

      assert %{Partition: "a", State: 1, LastSuccessfulObservation: 7, DeliveryId: 5} =
               result(message)

      assert Map.get(result(message), :Partitions) in [nil, []]
    end

    test "fails a deferral with a clear reason, since the kernel cannot defer" do
      message =
        Dispatch.build_result(state(UsersReactor), %{
          Partition: "a",
          Events: [event(Registered, "a", 7, "defer")]
        })

      assert %{State: 2, ExceptionStackTrace: reason} = result(message)
      assert reason =~ "cannot be deferred"
    end
  end

  describe "the handler" do
    setup do
      {:ok, lifecycle} = Lifecycle.start_link([])
      test = self()

      {:ok, handler} =
        Handler.start_link(
          module: UsersReactor,
          connection: :unused,
          event_store: "store",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: fn _state, _connection_id -> {:ok, :fake_stream, nil} end,
          send_fun: fn _stream, result -> send(test, {:sent, result}) end
        )

      Lifecycle.connected(lifecycle, "conn-1")
      Lifecycle.registered(lifecycle)
      _ = :sys.get_state(handler)
      %{handler: handler}
    end

    test "opts in to page delivery when it registers", %{handler: handler} do
      registration =
        handler
        |> :sys.get_state()
        |> Handler.build_registration("conn-1")
        |> Map.fetch!(:Content)
        |> Map.fetch!(:Value0)

      assert %{Enabled: true} = Map.fetch!(registration, :PageDelivery)
    end

    test "answers a page that spans partitions with one result per partition", %{
      handler: handler
    } do
      send(
        handler,
        {:event_batch,
         page([
           {"a", [event(Registered, "a", 1, "ann")]},
           {"b", [event(Registered, "b", 2, "bob")]}
         ])}
      )

      assert_receive {:sent, message}, 1_000
      assert map_size(by_partition(message)) == 2
    end
  end

  test "refuses to start a reactor whose event types reach more than one function" do
    Process.flag(:trap_exit, true)

    assert {:error, {%Chronicle.Observers.EventTypeObservedByMoreThanOneFunction{}, _}} =
             Handler.start_link(
               module: Confused,
               connection: :unused,
               event_store: "store",
               namespace: "Default"
             )
  end
end
