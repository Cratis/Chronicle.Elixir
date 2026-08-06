# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.HandlerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Reducers.Handler

  defmodule MyEvent do
    use Chronicle.Events.EventType, id: "my-event"
    defstruct [:amount]
  end

  defmodule MyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule TestReducer do
    use Chronicle.Reducers.Reducer, model: MyReadModel

    @handles MyEvent

    @impl true
    def reduce(%MyEvent{} = event, nil, _context), do: %MyReadModel{total: event.amount}

    def reduce(%MyEvent{} = event, model, _context),
      do: %{model | total: model.total + event.amount}
  end

  defmodule ReplayAwareReducer do
    use Chronicle.Reducers.Reducer, model: MyReadModel

    @handles MyEvent
    @receiver_name :reducer_handler_replay_test_receiver

    @impl true
    def reduce(%MyEvent{} = event, nil, _context), do: %MyReadModel{total: event.amount}

    @impl true
    def on_replay_begin, do: notify(:replay_begin)

    @impl true
    def on_replay_end, do: notify(:replay_end)

    @impl true
    def on_partition_replay_begin(partition), do: notify({:partition_replay_begin, partition})

    @impl true
    def on_partition_replay_end(partition), do: notify({:partition_replay_end, partition})

    defp notify(message) do
      case Process.whereis(@receiver_name) do
        nil -> :ok
        pid -> send(pid, message)
      end
    end
  end

  setup do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    establish_fun = fn _state, connection_id ->
      send(test, {:established, connection_id})
      {:ok, :fake_stream, nil}
    end

    {:ok, handler} =
      Handler.start_link(
        module: TestReducer,
        connection: :unused,
        event_store: "test",
        namespace: "Default",
        lifecycle: lifecycle,
        establish_fun: establish_fun
      )

    %{lifecycle: lifecycle, handler: handler}
  end

  test "does not register on :connected alone", %{lifecycle: lifecycle, handler: handler} do
    Lifecycle.connected(lifecycle, "conn-1")
    _ = Lifecycle.phase(lifecycle)
    refute_receive {:established, _}, 100
    assert :sys.get_state(handler).stream == nil
  end

  test "registers the observation stream on :registered with the connection id", %{
    lifecycle: lifecycle,
    handler: handler
  } do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    assert_receive {:established, "conn-1"}, 1_000
    assert :sys.get_state(handler).stream == :fake_stream
  end

  test "tears the stream down on :disconnected", %{lifecycle: lifecycle, handler: handler} do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-1"}, 1_000

    Lifecycle.disconnected(lifecycle)
    _ = Lifecycle.phase(lifecycle)
    assert :sys.get_state(handler).stream == nil
  end

  test "re-registers with a fresh connection id after reconnect", %{lifecycle: lifecycle} do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-1"}, 1_000

    Lifecycle.disconnected(lifecycle)
    Lifecycle.connected(lifecycle, "conn-2")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-2"}, 1_000
  end

  describe "replay lifecycle" do
    setup %{lifecycle: lifecycle} do
      Process.register(self(), :reducer_handler_replay_test_receiver)
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: ReplayAwareReducer,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun
        )

      Lifecycle.connected(lifecycle, "conn-1")
      Lifecycle.registered(lifecycle)
      %{handler: handler}
    end

    test "invokes on_replay_begin/0 and on_replay_end/0 without sending a ReducerResult", %{
      handler: handler
    } do
      send(handler, {:reduce_operation, %{Partition: "", ReplayState: :BeginReplay}})
      assert_receive :replay_begin, 1_000

      send(handler, {:reduce_operation, %{Partition: "", ReplayState: :EndReplay}})
      assert_receive :replay_end, 1_000
    end

    test "invokes on_partition_replay_begin/1 and on_partition_replay_end/1 with the partition",
         %{
           handler: handler
         } do
      send(
        handler,
        {:reduce_operation, %{Partition: "account-1", ReplayState: :BeginReplayPartition}}
      )

      assert_receive {:partition_replay_begin, "account-1"}, 1_000

      send(
        handler,
        {:reduce_operation, %{Partition: "account-1", ReplayState: :EndReplayPartition}}
      )

      assert_receive {:partition_replay_end, "account-1"}, 1_000
    end
  end
end
